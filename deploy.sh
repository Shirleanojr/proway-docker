#!/bin/bash

usage() {
  cat <<EOF
Set env

USAGE:  sudo ./env.sh --REPO_DIR [REPO_DIR] --BRANCH [BRANCH] --LOG_FILE [LOG_FILE]

ARGS:
  --REPO_DIR        Git local repository
  --BRANCH          Branch to track (e.g: main).
  --LOG_FILE        PATH log file

NOTES:
  - Your app repo must have a Dockerfile at its root.
  - If the repo lacks docker-compose.yml, a minimal one will be installed.
EOF
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --REPO_DIR) REPO_DIR="$2"; shift 2;;
    --BRANCH) BRANCH="$2" ; shift 2;;
    --LOG_FILE) LOG_FILE="$2" ; shift 2;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknow arg: $1" >&2; usage; exit 1;;
  esac
done


echo "Setting variables"
WORK_DIR="/opt/repos/"
SCRIPT_PATH="/opt/deploy"
APP_ENV="$SCRIPT_PATH/app.env"

echo "Creating default work folders"
mkdir -p $WORK_DIR
mkdir -p $SCRIPT_PATH

echo "Creating app environment variables"
cat > $APP_ENV <<EOF
REPO_DIR=$REPO_DIR
BRANCH=$BRANCH
LOG_FILE=$LOG_FILE/app.log
EOF

source $APP_ENV


echo "Updating package definitions"
apt update 

echo "Installing Dependencies"
apt install curl git -y
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

echo "Cloning App repository"
git clone -b "$BRANCH" "$REPO_DIR" "$WORK_DIR"

WORK_DIR="$WORK_DIR/pizzaria-app/"
echo "WORK_DIR=/opt/repos/pizzaria-app" >> $APP_ENV
source $APP_ENV



echo "Start App"
docker compose -f "$WORK_DIR"/docker-compose.yml up --build -d


echo "Set crontab for update local repo every new commit in main branch on github repo"
cat > $SCRIPT_PATH/cron-get-update.sh <<'EOF'
#!/bin/bash
source /opt/deploy/app.env


git -C "$WORK_DIR" fetch
remote_sha="$(git -C "$WORK_DIR" rev-parse "origin/$BRANCH")"
local_sha="$(git -C "$WORK_DIR" rev-parse "$BRANCH")"

echo remote_sha=$remote_sha
echo local_sha=$local_sha

if [[ "$remote_sha" != "$local_sha" ]]; then
  echo "$(date '+%F %T') [DEBUG] nova alteração encontrada $BRANCH @ $remote_sha" >> "$LOG_FILE"
  exit 0
fi
EOF

SCRIPT_PATH="$SCRIPT_PATH/cron-get-update.sh"
chmod +x $SCRIPT_PATH

CRON_JOB="* * * * * $SCRIPT_PATH"
(crontab -l 2>/dev/null | grep -Fv "$SCRIPT_PATH"; echo "$CRON_JOB") | crontab -
