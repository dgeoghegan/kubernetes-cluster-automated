#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Terraform multi-environment manager
#
# Layout assumed:
#   repo/
#     terraform/
#       infrastructure/          # shared TF config (source)
#       services/                # shared TF config (source)
#     management/
#       manage.sh                # this script
#       dev.tfvars               # env definition files (one or more)
#       prod.tfvars
#       aws_dev.ini              # credential files referenced by tfvars
#     environments/
#       dev/
#         infra/
#           root/                # env-specific working dir (symlinks to shared config)
#           .terraform/          # env-specific TF data dir
#           files_from_terraform/
#         services/
#           root/
#           .terraform/
#       prod/...
#
# Notes:
# - We run Terraform from env-specific working dirs so each env has its own
#   .terraform.lock.hcl, init artifacts, and any generated files.
# - The working dir contains symlinks to the shared terraform roots.
# ============================================================

# ---------- Paths ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$REPO_ROOT" ]]; then
  echo "Error: not inside a git repo; cannot locate repo root." >&2
  exit 1
fi

MGMT_DIR="$SCRIPT_DIR"
ENVIRONMENTS_DIR="$REPO_ROOT/environments"

TF_SRC_INFRA="$REPO_ROOT/terraform/infrastructure"
TF_SRC_SERVICES="$REPO_ROOT/terraform/services"

PLAYBOOKS_DIR="$REPO_ROOT/ansible/playbooks"

# Terraform: readable logs (no ANSI color)
export TF_CLI_ARGS_init="-no-color"
export TF_CLI_ARGS_plan="-no-color"
export TF_CLI_ARGS_apply="-no-color"
export TF_CLI_ARGS_destroy="-no-color"

# ---------- UX helpers ----------
bold() { tput bold 2>/dev/null || true; }
sgr0() { tput sgr0 2>/dev/null || true; }
headline() { echo -e "$(bold)=== $* ===$(sgr0)"; }
timestamp() { date +"%Y%m%d_%H%M%S"; }

die() { echo "Error: $*" >&2; exit 1; }

# ---------- Terraform presence/version ----------
check_terraform() {
  command -v terraform >/dev/null 2>&1 || die "terraform not found. Install Terraform and ensure it's in PATH."
  terraform version >/dev/null 2>&1 || die "terraform is installed but not working (terraform version failed)."

  # Optional: enforce a minimum version (edit as you like)
  local min="1.5.0"
  local cur
  cur="$(terraform version -json 2>/dev/null | awk -F'"' '/"terraform_version":/{print $4; exit}' || true)"
  if [[ -n "$cur" ]]; then
    # naive semver compare using sort -V
    if [[ "$(printf '%s\n%s\n' "$min" "$cur" | sort -V | head -n1)" != "$min" ]]; then
      die "terraform version $cur found, but >= $min is required."
    fi
  fi
}

# ---------- Env discovery & selection ----------
is_base_env_tfvars() {
  local f
  f="$(basename "$1")"

  # Must be exactly <env>.tfvars (no extra dots)
  [[ "$f" =~ ^[a-zA-Z0-9_-]+\.tfvars$ ]] || return 1
  return 0
}


list_env_tfvars() {
  local f
  for f in "$MGMT_DIR"/*.tfvars; do
    [[ -e "$f" ]] || continue
    if is_base_env_tfvars "$(basename "$f")"; then
      echo "$f"
    fi
  done
}

env_name_from_tfvars_path() {
  local path="$1"
  local base
  base="$(basename "$path")"          # dev.tfvars
  echo "${base%.tfvars}"             # dev
}

pick_env() {
  local env_files=()

  # Collect base env tfvars
  while IFS= read -r f; do
    env_files+=("$f")
  done < <(list_env_tfvars)

  if (( ${#env_files[@]} == 0 )); then
    die "No environment tfvars found in $MGMT_DIR (expected e.g. dev.tfvars)."
  fi

  # Sort alphabetically by env name
  IFS=$'\n' env_files=($(printf '%s\n' "${env_files[@]}" | sort))
  unset IFS

  # If only one env, select automatically
  if (( ${#env_files[@]} == 1 )); then
    echo "${env_files[0]}"
    return 0
  fi

  headline "Select environment" >&2
  local i
  for i in "${!env_files[@]}"; do
    local name
    name="$(env_name_from_tfvars_path "${env_files[$i]}")"
    printf "  %d) %s\n" "$((i+1))" "$name" >&2
  done

  local choice
  while true; do
    read -rp "Select environment number: " choice
    [[ "$choice" =~ ^[0-9]+$ ]] || { echo "Enter a number."; continue; }
    (( choice >= 1 && choice <= ${#env_files[@]} )) || { echo "Out of range."; continue; }
    printf '%s\n' "${env_files[$((choice-1))]}"
    return 0
  done
}

# ---------- Minimal tfvars parsing ----------
# Extracts value of: key = "value" (or key = value)
# Does not try to evaluate expressions beyond simple ${path.module} substitution.
tfvars_get() {
  local file="$1" key="$2"
  awk -v k="$key" '
    BEGIN{FS="="}
    /^[[:space:]]*#/ {next}
    $0 ~ "^[[:space:]]*" k "[[:space:]]*=" {
      v=$2
      sub(/^[[:space:]]*/, "", v)
      sub(/[[:space:]]*$/, "", v)
      gsub(/^"/, "", v); gsub(/"$/, "", v)
      print v
      exit
    }
  ' "$file"
}

expand_path_module() {
  local raw="$1"
  # Replace literal ${path.module} with management dir
  echo "${raw//'${path.module}'/$MGMT_DIR}"
}

# ---------- Env runtime dirs ----------
# Populated after env selection
ENV_TFVARS=""
ENV_NAME=""
ENV_ROOT=""

INFRA_DIR=""        # env runtime: environments/<env>/infra
SERVICES_DIR=""     # env runtime: environments/<env>/services
LOG_DIR=""

INFRA_WORKDIR=""    # environments/<env>/infra/root
SERVICES_WORKDIR="" # environments/<env>/services/root
INFRA_TF_DATA_DIR=""    # environments/<env>/infra/.terraform
SERVICES_TF_DATA_DIR="" # environments/<env>/services/.terraform

# Optional per-root override tfvars in management/
INFRA_OVERRIDE_TFVARS=""     # management/<env>.infra.tfvars (optional)
SERVICES_OVERRIDE_TFVARS=""  # management/<env>.services.tfvars (optional)

# ---------- Workdir sync (symlink shared TF source into per-env workdir) ----------
sync_workdir() {
  local src="$1" work="$2"

  [[ -d "$src" ]] || die "Missing terraform source dir: $src"
  mkdir -p "$work"

  # Remove stale symlinks that no longer have corresponding src entries
  local entry name
  shopt -s dotglob nullglob
  for entry in "$work"/*; do
    name="$(basename "$entry")"
    [[ "$name" == ".terraform" ]] && continue
    [[ "$name" == ".terraform.lock.hcl" ]] && continue
    [[ "$name" == "terraform.tfstate" ]] && continue
    [[ "$name" == "terraform.tfstate.backup" ]] && continue
    [[ "$name" == "root" ]] && continue

    if [[ -L "$entry" ]]; then
      if [[ ! -e "$src/$name" ]]; then
        rm -f "$entry"
      fi
    fi
  done
  shopt -u dotglob nullglob

  # Symlink all entries from src into work (excluding tfstate-ish artifacts)
  shopt -s dotglob nullglob
  for entry in "$src"/*; do
    name="$(basename "$entry")"
    [[ "$name" == ".terraform" ]] && continue
    [[ "$name" == ".terraform.lock.hcl" ]] && continue
    [[ "$name" == "terraform.tfstate" ]] && continue
    [[ "$name" == "terraform.tfstate.backup" ]] && continue
    [[ "$name" == "logs" ]] && continue

    ln -sfn "$entry" "$work/$name"
  done
  shopt -u dotglob nullglob
}

# ---------- Var-file args ----------
# Precedence: base env tfvars, then optional per-root override tfvars.
tfvar_args_for() {
  local root="$1"
  local -n out="$2"

  out=()
  out+=(-var-file="$ENV_TFVARS")

  if [[ "$root" == "infra" && -f "$INFRA_OVERRIDE_TFVARS" ]]; then
    out+=(-var-file="$INFRA_OVERRIDE_TFVARS")
  elif [[ "$root" == "services" && -f "$SERVICES_OVERRIDE_TFVARS" ]]; then
    out+=(-var-file="$SERVICES_OVERRIDE_TFVARS")
  fi

  if [[ "$root" == "services" ]]; then
    out+=(-var="playbooks_dir=$PLAYBOOKS_DIR")
  fi
}

# ---------- Terraform init detection ----------
needs_init() {
  local workdir="$1" tf_data_dir="$2"

  # If TF data dir not present, init required
  if [[ ! -d "$tf_data_dir" ]]; then
    return 0
  fi

  # Lock file is in the working dir; if missing, init required
  if [[ ! -f "$workdir/.terraform.lock.hcl" ]]; then
    return 0
  fi

  # Check modules are available
  if ! (cd "$workdir" && TF_DATA_DIR="$tf_data_dir" terraform get -no-color >/dev/null 2>&1); then
    return 0
  fi

  return 1
}

tf_init_if_needed() {
  local workdir="$1" tf_data_dir="$2" rootname="$3"
  if needs_init "$workdir" "$tf_data_dir"; then
    headline "terraform init ($rootname)"
    (cd "$workdir" && TF_DATA_DIR="$tf_data_dir" terraform init -upgrade -reconfigure)
  else
    headline "init not needed ($rootname)"
  fi
}

# ---------- Logging runner ----------
run_tf() {
  local action="$1"      # plan|apply|destroy
  local workdir="$2"     # env-specific workdir (symlinked config)
  local tf_data_dir="$3" # env-specific TF_DATA_DIR
  local rootname="$4"    # infra|services

  echo "Using env tfvars: $ENV_TFVARS"

  # Ensure workdir is synced to shared TF source
  if [[ "$rootname" == "infra" ]]; then
    sync_workdir "$TF_SRC_INFRA" "$workdir"
  else
    sync_workdir "$TF_SRC_SERVICES" "$workdir"
  fi

  # Init if required
  tf_init_if_needed "$workdir" "$tf_data_dir" "$rootname"

  local ts log
  ts="$(timestamp)"
  log="$LOG_DIR/terraform_${ts}_${ENV_NAME}_${rootname}_${action}.log"

  # Build terraform argv as an array (CRITICAL FIX)
  local args=()
  tfvar_args_for "$rootname" args

  headline "terraform $action ($ENV_NAME / $rootname)"

  case "$action" in
    plan)
      set -x
      (
        cd "$workdir" &&
        TF_DATA_DIR="$tf_data_dir" \
        terraform plan "${args[@]}"
      ) | tee "$log"
      set +x
      ;;
    apply)
      set -x
      (
        cd "$workdir" &&
        TF_DATA_DIR="$tf_data_dir" \
        terraform apply -auto-approve "${args[@]}"
      ) | tee "$log"
      set +x
      ;;
    destroy)
      set -x
      (
        cd "$workdir" &&
        TF_DATA_DIR="$tf_data_dir" \
        terraform destroy -auto-approve "${args[@]}"
      ) | tee "$log"
      set +x
      ;;
    *)
      die "Unknown terraform action: $action"
      ;;
  esac

  echo "Log: $log"
}


# ---------- Validation ----------
get_backend_from_env_tfvars() {
  local v
  v="$(tfvars_get "$ENV_TFVARS" "backend_type" || true)"
  echo "$v"
}

get_cloud_type_from_env_tfvars() {
  local v
  v="$(tfvars_get "$ENV_TFVARS" "cloud_type" || true)"
  echo "$v"
}

get_aws_credentials_file_from_env_tfvars() {
  local v
  v="$(tfvars_get "$ENV_TFVARS" "aws_credentials_file" || true)"
  [[ -n "$v" ]] || return 0
  expand_path_module "$v"
}

validate_config() {
  local CONTINUE_ON_FAIL="${1:-ask}"
  headline "Validating configuration"
  local errs=()

  [[ -d "$TF_SRC_INFRA" ]] || errs+=("Missing terraform source: $TF_SRC_INFRA")
  [[ -d "$TF_SRC_SERVICES" ]] || errs+=("Missing terraform source: $TF_SRC_SERVICES")
  [[ -d "$PLAYBOOKS_DIR" ]] || errs+=("Missing playbooks dir: $PLAYBOOKS_DIR")
  [[ -f "$ENV_TFVARS" ]] || errs+=("Missing env tfvars: $ENV_TFVARS")

  mkdir -p "$INFRA_DIR" "$SERVICES_DIR" "$INFRA_WORKDIR" "$SERVICES_WORKDIR" "$INFRA_TF_DATA_DIR" "$SERVICES_TF_DATA_DIR" "$LOG_DIR"

  # Backend and credential checks (minimal policy; you can tighten later)
  local backend cloud aws_creds
  backend="$(get_backend_from_env_tfvars || true)"
  cloud="$(get_cloud_type_from_env_tfvars || true)"
  aws_creds="$(get_aws_credentials_file_from_env_tfvars || true)"

  # If cloud is aws OR backend is s3, require aws_credentials_file be set and exist
  if [[ "$cloud" == "aws" || "$backend" == "s3" ]]; then
    [[ -n "$aws_creds" ]] || errs+=("cloud_type=aws or backend_type=s3 but aws_credentials_file not set in $ENV_TFVARS")
    if [[ -n "$aws_creds" && ! -f "$aws_creds" ]]; then
      errs+=("aws_credentials_file points to missing file: $aws_creds")
    fi
  fi

  if (( ${#errs[@]} )); then
    printf '%s\n' "${errs[@]}" >&2
    if [[ "$CONTINUE_ON_FAIL" == "yes" ]]; then
      echo "Continuing despite validation errors."
    else
      echo
      read -rp "Abort? [Y/n] " ans
      ans="${ans:-Y}"
      [[ "$ans" =~ ^[Yy]$ ]] && exit 2
    fi
  else
    echo "OK"
  fi
}

# ---------- High-level actions ----------
plan_both()    { run_tf plan    "$INFRA_WORKDIR"    "$INFRA_TF_DATA_DIR"    infra && run_tf plan    "$SERVICES_WORKDIR" "$SERVICES_TF_DATA_DIR" services; }
apply_both()   { run_tf apply   "$INFRA_WORKDIR"    "$INFRA_TF_DATA_DIR"    infra && run_tf apply   "$SERVICES_WORKDIR" "$SERVICES_TF_DATA_DIR" services; }

destroy_both() {
  echo
  headline "Destroy confirmation"
  echo "You are about to DESTROY:"
  echo "  Environment: $ENV_NAME"
  echo "  Order: services -> infra"
  echo
  read -rp "Type the environment name to confirm destroy: " typed
  [[ "$typed" == "$ENV_NAME" ]] || { echo "Confirmation failed. Aborting."; return 1; }
  run_tf destroy "$SERVICES_WORKDIR" "$SERVICES_TF_DATA_DIR" services
  run_tf destroy "$INFRA_WORKDIR"    "$INFRA_TF_DATA_DIR"    infra
}

plan_infra()     { run_tf plan    "$INFRA_WORKDIR"    "$INFRA_TF_DATA_DIR"    infra; }
apply_infra()    { run_tf apply   "$INFRA_WORKDIR"    "$INFRA_TF_DATA_DIR"    infra; }
destroy_infra()  {
  echo
  headline "Destroy confirmation"
  echo "You are about to DESTROY infra for environment: $ENV_NAME"
  read -rp "Type the environment name to confirm destroy: " typed
  [[ "$typed" == "$ENV_NAME" ]] || { echo "Confirmation failed. Aborting."; return 1; }
  run_tf destroy "$INFRA_WORKDIR" "$INFRA_TF_DATA_DIR" infra
}

plan_services()    { run_tf plan    "$SERVICES_WORKDIR" "$SERVICES_TF_DATA_DIR" services; }
apply_services()   { run_tf apply   "$SERVICES_WORKDIR" "$SERVICES_TF_DATA_DIR" services; }
destroy_services() {
  echo
  headline "Destroy confirmation"
  echo "You are about to DESTROY services for environment: $ENV_NAME"
  read -rp "Type the environment name to confirm destroy: " typed
  [[ "$typed" == "$ENV_NAME" ]] || { echo "Confirmation failed. Aborting."; return 1; }
  run_tf destroy "$SERVICES_WORKDIR" "$SERVICES_TF_DATA_DIR" services
}

tail_logs() {
  local last
  last="$(ls -1t "$LOG_DIR"/terraform_*.log 2>/dev/null | head -n1 || true)"
  if [[ -n "$last" ]]; then
    headline "Tailing $last (Ctrl-C to exit)"
    tail -f "$last"
  else
    echo "No logs yet."
  fi
}

ssh_menu() {
  local menu="$REPO_ROOT/docker/ssh_menu.sh"
  if [[ ! -x "$menu" ]]; then
    echo "Missing or non-executable: $menu" >&2
    exit 3
  fi
  # Historically passed infrastructure root; now pass env infra runtime dir
  exec "$menu" "$INFRA_DIR" "$INFRA_WORKDIR"
}

kubectl_shell() {
  headline "Starting interactive kubectl shell"

  # Ensure workdirs exist and are synced so outputs are readable even before you run apply
  sync_workdir "$TF_SRC_INFRA" "$INFRA_WORKDIR"
  sync_workdir "$TF_SRC_SERVICES" "$SERVICES_WORKDIR"

  local docker_ip registry_address registry_user registry_pass kubectl_image
  docker_ip="$(cd "$INFRA_WORKDIR" && TF_DATA_DIR="$INFRA_TF_DATA_DIR" terraform output -raw docker_server_public_ip 2>/dev/null || true)"
  registry_address="$(cd "$SERVICES_WORKDIR" && TF_DATA_DIR="$SERVICES_TF_DATA_DIR" terraform output -raw registry_address 2>/dev/null || true)"
  registry_user="$(cd "$SERVICES_WORKDIR" && TF_DATA_DIR="$SERVICES_TF_DATA_DIR" terraform output -raw registry_user 2>/dev/null || true)"
  registry_pass="$(cd "$SERVICES_WORKDIR" && TF_DATA_DIR="$SERVICES_TF_DATA_DIR" terraform output -raw registry_pass 2>/dev/null || true)"
  kubectl_image="$(cd "$SERVICES_WORKDIR" && TF_DATA_DIR="$SERVICES_TF_DATA_DIR" terraform output -raw kubectl_image_remote 2>/dev/null || true)"

  [[ -n "$docker_ip" ]] || { echo "❌ Could not determine docker-server IP via Terraform outputs."; return 1; }

  # SSH key generated by Terraform should now live under env runtime (infra)
  local ssh_key="$INFRA_WORKDIR/files_from_terraform/docker_ssh_key"
  [[ -f "$ssh_key" ]] || { echo "❌ SSH key not found at $ssh_key"; return 1; }

  headline "Connecting to docker-server at $docker_ip"
  echo "You will be dropped into a kubectl-enabled shell."
  echo

  ssh -tt -i "$ssh_key" -o StrictHostKeyChecking=no ubuntu@"$docker_ip" \
    "docker login ${registry_address} -u ${registry_user} -p '${registry_pass}' && \
     docker run -it --rm \
       -v /ansible:/ansible \
       -e KUBECONFIG=/ansible/common/admin_kubeconfig \
       --entrypoint /bin/sh \
       ${kubectl_image} "
}

# ---------- Menu ----------
show_menu() {
  cat <<'MENU'
Choose an action:
  1) Validate config only
  2) Init if needed (infra & services)
  3) Plan both (infra -> services)
  4) Apply both (infra -> services)
  5) Plan infra only
  6) Apply infra only
  7) Plan services only
  8) Apply services only
  9) Tail latest logs
  10) Destroy both (services -> infra)
  S) SSH into a server
  K) Kubectl shell (interactive)
  Q) Quit
MENU
}

ensure_env_dirs() {
  [[ -n "${ENV_ROOT:-}" ]] || {
    echo "BUG: ensure_env_dirs called before setup_env" >&2
    exit 99
  }
  echo "DEBUG: ensure_env_dirs called"

  mkdir -p \
    "$INFRA_DIR" \
    "$SERVICES_DIR" \
    "$INFRA_WORKDIR" \
    "$SERVICES_WORKDIR" \
    "$INFRA_TF_DATA_DIR" \
    "$SERVICES_TF_DATA_DIR" \
    "$LOG_DIR"

  sync_workdir "$TF_SRC_INFRA" "$INFRA_WORKDIR"
  sync_workdir "$TF_SRC_SERVICES" "$SERVICES_WORKDIR"
}

init_both_if_needed() {
  validate_config "ask"
  tf_init_if_needed "$INFRA_WORKDIR" "$INFRA_TF_DATA_DIR" infra
  tf_init_if_needed "$SERVICES_WORKDIR" "$SERVICES_TF_DATA_DIR" services
}

# ---------- Setup selected env ----------
setup_env() {
# if env already selected, take no action
  ENV_TFVARS="$(pick_env | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  ENV_NAME="$(env_name_from_tfvars_path "$ENV_TFVARS")"
  ENV_ROOT="$ENVIRONMENTS_DIR/$ENV_NAME"

  INFRA_DIR="$ENV_ROOT/infra"
  SERVICES_DIR="$ENV_ROOT/services"
  LOG_DIR="$ENV_ROOT/logs"

  INFRA_WORKDIR="$INFRA_DIR/root"
  SERVICES_WORKDIR="$SERVICES_DIR/root"

  INFRA_TF_DATA_DIR="$INFRA_DIR/.terraform"
  SERVICES_TF_DATA_DIR="$SERVICES_DIR/.terraform"

  INFRA_OVERRIDE_TFVARS="$MGMT_DIR/${ENV_NAME}.infra.tfvars"
  SERVICES_OVERRIDE_TFVARS="$MGMT_DIR/${ENV_NAME}.services.tfvars"

  ensure_env_dirs
}

# ---------- Main ----------
main() {
  check_terraform
  setup_env

  headline "Terraform environment manager"
  echo "Repo root:        $REPO_ROOT"
  echo "Management dir:   $MGMT_DIR"
  echo "Selected env:     $ENV_NAME"
  echo "Env tfvars:       $(basename "$ENV_TFVARS")"
  echo
  echo "Terraform sources:"
  echo "  infra:          $TF_SRC_INFRA"
  echo "  services:       $TF_SRC_SERVICES"
  echo
  echo "Env runtime dirs:"
  echo "  infra runtime:  $INFRA_DIR"
  echo "  services rt:    $SERVICES_DIR"
  echo "  logs:           $LOG_DIR"
  echo
  echo "Before running, ensure:"
  echo "  • env tfvars is configured in management/"
  echo "  • any credential files referenced by tfvars exist"
  echo

  while true; do
    show_menu
    read -rp "> " choice
    case "$choice" in
      1) validate_config "ask" ;;
      2) init_both_if_needed ;;
      3) validate_config "ask"; plan_both ;;
      4) validate_config "ask"; apply_both ;;
      5) validate_config "ask"; plan_infra ;;
      6) validate_config "ask"; apply_infra ;;
      7) validate_config "ask"; plan_services ;;
      8) validate_config "ask"; apply_services ;;
      9) tail_logs ;;
      10) validate_config "ask"; destroy_both ;;
      s|S) ssh_menu ;;
      k|K) validate_config "ask"; kubectl_shell ;;
      q|Q) exit 0 ;;
      *) echo "Invalid choice." ;;
    esac
    echo
  done
}

main "$@"

