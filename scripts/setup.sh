#!/usr/bin/env bash
# Interactive setup wizard: asks for the project settings, validates them and writes
#   infra/bootstrap/terraform.tfvars
#   infra/environments/dev/terraform.tfvars
#   infra/environments/prod/terraform.tfvars
#   infra/environments/prod/backend.hcl
# by copying the matching *.example files and filling in the answers. It can also patch the
# placeholders in infra/iam/*-policy.json and write the result to infra/iam/rendered/ (gitignored).
#
# Usage: scripts/setup.sh [--force]    (--force overwrites existing files without asking)
# Secrets (reCAPTCHA secret key) are never asked for or written; see docs/INFRA.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

BOOT_DIR="$ROOT/infra/bootstrap"
DEV_DIR="$ROOT/infra/environments/dev"
PROD_DIR="$ROOT/infra/environments/prod"

say()  { printf '%s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

# Value of `key = "value"` in a file, empty if the file or key is missing.
existing() {
  [ -f "$2" ] || return 0
  sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"([^\"]*)\".*/\1/p" "$2" | head -n1
}

# ask VAR "Prompt" "default" validator_function "hint"
# Re-asks until the validator accepts the answer.
ask() {
  local var=$1 prompt=$2 default=$3 check=$4 hint=$5 answer
  while true; do
    if [ -n "$default" ]; then
      read -r -p "$prompt [$default]: " answer || die "input closed"
      answer=${answer:-$default}
    else
      read -r -p "$prompt: " answer || die "input closed"
    fi
    if "$check" "$answer"; then
      printf -v "$var" '%s' "$answer"
      return
    fi
    say "  invalid: $hint"
  done
}

yes_no() { # yes_no "Question" default(y|n)
  local answer def=$2 hint="y/N"
  [ "$def" = y ] && hint="Y/n"
  read -r -p "$1 [$hint]: " answer || die "input closed"
  answer=${answer:-$def}
  [[ $answer =~ ^[Yy] ]]
}

# --- validators -------------------------------------------------------------
v_project() { [[ $1 =~ ^[a-z0-9]([a-z0-9.-]{1,38})[a-z0-9]$ ]]; }
v_region()  { [[ $1 =~ ^[a-z]{2}(-gov)?-[a-z]+-[0-9]$ ]]; }
v_domain()  { [[ $1 =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$ ]]; }
v_email()   { [[ $1 =~ ^[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+\.)+[A-Za-z]{2,}$ ]]; }
v_owner()   { [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9\ _.@-]{0,62}$ ]]; }
v_boundary(){ [ "$1" = none ] || [[ $1 =~ ^arn:aws:iam::[0-9]{12}:policy/[A-Za-z0-9+=,.@_/-]+$ ]]; }

v_bucket()  { [[ $1 =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ && $1 != *..* && ! $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; }
v_account() { [[ $1 =~ ^[0-9]{12}$ ]]; }
v_iamuser() { [[ $1 =~ ^[A-Za-z0-9+=,.@_-]{1,64}$ ]]; }

# --- file helpers -----------------------------------------------------------
# set_value FILE KEY VALUE: replaces `KEY = "..."` keeping the original spacing.
# Values are validated above, so they contain no sed-special characters (| & \).
set_value() {
  local file=$1 key=$2 value=$3 tmp
  tmp=$(mktemp)
  sed -E "s|^([[:space:]]*$key[[:space:]]*=[[:space:]]*)\"[^\"]*\"|\1\"$value\"|" "$file" > "$tmp"
  mv "$tmp" "$file"
  grep -qE "^[[:space:]]*$key[[:space:]]*=[[:space:]]*\"$value\"" "$file" || die "could not set $key in $file"
}

# render SRC DEST: copy SRC to DEST unless the user declines to overwrite an existing DEST.
# Returns 1 when skipped.
render() {
  local src=$1 dest=$2
  [ -f "$src" ] || die "missing template: ${src#"$ROOT"/}"
  if [ -e "$dest" ] && [ "$FORCE" -eq 0 ]; then
    yes_no "${dest#"$ROOT"/} already exists. Overwrite?" n || { say "  skipped ${dest#"$ROOT"/}"; return 1; }
  fi
  cp "$src" "$dest"
}

# --- questions --------------------------------------------------------------
say "Project setup wizard. Press Enter to accept the [default]."
say ""

PREV="$PROD_DIR/terraform.tfvars"
ask PROJECT "Project name (lowercase letters, digits, - and .; used in resource names and as the default for bucket names)" \
  "$(existing project_name "$PREV")" v_project "3-40 chars: a-z, 0-9, '-' or '.', starting and ending with a letter or digit"
ask REGION "AWS region for the site, API and state bucket" \
  "$(existing aws_region "$PREV" | grep . || echo eu-west-3)" v_region "expected a region like eu-west-3"
# Bucket names are global across all AWS accounts, so they are stored explicitly in the configs.
ask STATE_BUCKET "State bucket name (globally unique; created by 'make bootstrap')" \
  "$(existing state_bucket_name "$BOOT_DIR/terraform.tfvars" | grep . || echo "$PROJECT-tofu-state")" v_bucket \
  "3-63 chars: a-z, 0-9, '-' or '.', starting and ending with a letter or digit"
ask SITE_BUCKET "Prod site bucket name (globally unique)" \
  "$(existing site_bucket_name "$PREV" | grep . || echo "$PROJECT-prod-site")" v_bucket "same rules as the state bucket"
ask DEV_SITE_BUCKET "Dev site bucket name (globally unique)" \
  "$(existing site_bucket_name "$DEV_DIR/terraform.tfvars" | grep . || echo "$PROJECT-dev-site")" v_bucket "same rules as the state bucket"
if [ "$STATE_BUCKET" = "$SITE_BUCKET" ] || [ "$STATE_BUCKET" = "$DEV_SITE_BUCKET" ] || [ "$SITE_BUCKET" = "$DEV_SITE_BUCKET" ]; then
  die "the state, prod site and dev site buckets must have different names"
fi
ask DOMAIN "Site domain (apex, no www)" "$(existing domain_name "$PREV")" v_domain "expected a domain like example.com"
ask SES_EMAIL "Contact form sender/recipient email (SES identity)" "$(existing ses_email "$PREV")" v_email "expected an email address"
ask ADMIN_EMAIL "Admin email for budget alerts" "$(existing admin_email "$PREV")" v_email "expected an email address"
ask OWNER "Owner tag" "$(existing Owner "$PREV")" v_owner "letters, digits, space and _ . @ - only"
ask BOUNDARY "IAM permissions boundary ARN (type 'none' if you do not use one)" \
  "$(existing iam_permissions_boundary_arn "$PREV" | grep . || echo none)" v_boundary \
  "expected arn:aws:iam::<12-digit account>:policy/<name>, or 'none'"
[ "$BOUNDARY" = none ] && BOUNDARY=""

# Optional sanity check against the current AWS identity (never fatal).
if command -v aws >/dev/null 2>&1 && ACCOUNT=$(AWS_PAGER="" aws sts get-caller-identity --query Account --output text 2>/dev/null); then
  say ""
  say "Current AWS account: $ACCOUNT"
  if [ -n "$BOUNDARY" ] && [[ $BOUNDARY != arn:aws:iam::$ACCOUNT:* ]]; then
    say "  warning: the boundary ARN belongs to a different account than your current credentials."
  fi
else
  say ""
  say "(AWS identity not checked: no valid credentials. Run 'aws sso login' if you want this check.)"
fi

say ""
RENDER_IAM=0
if yes_no "Also patch the IAM policy templates (infra/iam/*-policy.json) with these values?" y; then
  RENDER_IAM=1
  ask ACCOUNT_ID "AWS account ID" "${ACCOUNT:-}" v_account "expected 12 digits"
  ask TARGET_USER "IAM user that will run tofu (policies are scoped to it)" "$PROJECT" v_iamuser \
    "1-64 chars: letters, digits and + = , . @ _ -"
fi

say ""
say "Summary"
say "  project_name   $PROJECT"
say "  aws_region     $REGION"
say "  domain_name    $DOMAIN"
say "  ses_email      $SES_EMAIL"
say "  admin_email    $ADMIN_EMAIL"
say "  Owner tag      $OWNER"
say "  boundary ARN   ${BOUNDARY:-<none>}"
say "  state bucket   $STATE_BUCKET"
say "  prod site      $SITE_BUCKET"
say "  dev site       $DEV_SITE_BUCKET"
if [ "$RENDER_IAM" -eq 1 ]; then
  say "  IAM account    $ACCOUNT_ID"
  say "  IAM user       $TARGET_USER"
fi
say ""
yes_no "Write the configuration files with these values?" y || { say "Aborted, nothing written."; exit 1; }

# --- write files ------------------------------------------------------------
say ""
if render "$BOOT_DIR/terraform.tfvars.example" "$BOOT_DIR/terraform.tfvars"; then
  f="$BOOT_DIR/terraform.tfvars"
  set_value "$f" project_name "$PROJECT"
  set_value "$f" aws_region "$REGION"
  set_value "$f" state_bucket_name "$STATE_BUCKET"
  set_value "$f" Owner "$OWNER"
  say "  wrote infra/bootstrap/terraform.tfvars"
fi

if render "$DEV_DIR/terraform.tfvars.example" "$DEV_DIR/terraform.tfvars"; then
  f="$DEV_DIR/terraform.tfvars"
  set_value "$f" project_name "$PROJECT"
  set_value "$f" aws_region "$REGION"
  set_value "$f" site_bucket_name "$DEV_SITE_BUCKET"
  set_value "$f" Owner "$OWNER"
  if [ -n "$BOUNDARY" ]; then # the dev example ships this line commented out
    tmp=$(mktemp)
    sed -E "s|^#[[:space:]]*(iam_permissions_boundary_arn[[:space:]]*=).*|\1 \"$BOUNDARY\"|" "$f" > "$tmp" && mv "$tmp" "$f"
  fi
  say "  wrote infra/environments/dev/terraform.tfvars"
fi

if render "$PROD_DIR/terraform.tfvars.example" "$PROD_DIR/terraform.tfvars"; then
  f="$PROD_DIR/terraform.tfvars"
  set_value "$f" project_name "$PROJECT"
  set_value "$f" aws_region "$REGION"
  set_value "$f" site_bucket_name "$SITE_BUCKET"
  set_value "$f" domain_name "$DOMAIN"
  set_value "$f" ses_email "$SES_EMAIL"
  set_value "$f" admin_email "$ADMIN_EMAIL"
  set_value "$f" Owner "$OWNER"
  if [ -n "$BOUNDARY" ]; then
    set_value "$f" iam_permissions_boundary_arn "$BOUNDARY"
  else # the prod example ships a placeholder ARN; drop it when no boundary is used
    tmp=$(mktemp)
    grep -vE '^[[:space:]]*iam_permissions_boundary_arn[[:space:]]*=' "$f" > "$tmp" && mv "$tmp" "$f"
  fi
  say "  wrote infra/environments/prod/terraform.tfvars"
fi

if render "$PROD_DIR/backend.hcl.example" "$PROD_DIR/backend.hcl"; then
  f="$PROD_DIR/backend.hcl"
  set_value "$f" bucket "$STATE_BUCKET"
  set_value "$f" region "$REGION"
  say "  wrote infra/environments/prod/backend.hcl"
fi

if [ "$RENDER_IAM" -eq 1 ]; then
  IAM_DIR="$ROOT/infra/iam"
  OUT_DIR="$IAM_DIR/rendered"
  mkdir -p "$OUT_DIR"
  PROJECT_SAFE=${PROJECT//./-} # Lambda, role and log group names cannot contain dots
  for name in deploy bootstrap credentials-admin; do
    src="$IAM_DIR/$name-policy.json"
    dest="$OUT_DIR/$name-policy.json"
    render "$src" "$dest" || continue
    tmp=$(mktemp)
    # PROJECT_SAFE must be replaced before PROJECT, as one is a prefix of the other.
    sed -e "s|DEV_SITE_BUCKET|$DEV_SITE_BUCKET|g" -e "s|SITE_BUCKET|$SITE_BUCKET|g" \
        -e "s|STATE_BUCKET|$STATE_BUCKET|g" \
        -e "s|PROJECT_SAFE|$PROJECT_SAFE|g" -e "s|PROJECT|$PROJECT|g" -e "s|ACCOUNT_ID|$ACCOUNT_ID|g" \
        -e "s|REGION|$REGION|g" -e "s|TARGET_USER|$TARGET_USER|g" "$dest" > "$tmp"
    mv "$tmp" "$dest"
    if grep -qE 'PROJECT|STATE_BUCKET|SITE_BUCKET|ACCOUNT_ID|REGION|TARGET_USER' "$dest"; then
      die "unreplaced placeholder left in ${dest#"$ROOT"/}"
    fi
    if command -v python3 >/dev/null 2>&1; then
      python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$dest" || die "invalid JSON in ${dest#"$ROOT"/}"
    fi
    say "  wrote infra/iam/rendered/$name-policy.json"
  done
fi

cat <<NEXT

Done. Not set by this wizard (kept out of files on purpose):
  - reCAPTCHA secret:  export TF_VAR_recaptcha_secret_key_env='<secret>'
  - reCAPTCHA site key: edit <meta name="recaptcha-site-key"> in website/index.html

Next:
  create the IAM policies from infra/iam/rendered/*.json as an admin (see infra/iam/README.md)
  make bootstrap
  make prod-apply
NEXT
