#!/usr/bin/env bash
# ONE command sets up everything on a fresh Ubuntu 24.04 EC2 (t3.large, 30 GB):
#   Docker + private image registry + k3s Kubernetes + a Git server + fully pre-configured Jenkins
#   with the 3 PBL jobs, then runs every pipeline once so all three apps are live.
# Usage:  sudo bash scripts/setup.sh        (safe to run again if anything fails)
set -euo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
U="${SUDO_USER:-ubuntu}"
GIT_BARE=/srv/git/medicare-devops.git
WORK=/opt/medicare-work
PASS_FILE=/root/jenkins-admin-password.txt
[ "$(id -u)" -eq 0 ] || { echo "Please run with sudo:  sudo bash scripts/setup.sh"; exit 1; }
step() { echo; echo "================  $*  ================"; }

step "1/7  Installing Docker and tools"
apt-get update -y
apt-get install -y docker.io curl git openssl unzip
apt-get install -y docker-buildx 2>/dev/null || true
systemctl enable --now docker
usermod -aG docker "$U" || true

step "2/7  Private Docker image registry (localhost:5000)"
docker start registry >/dev/null 2>&1 || docker run -d --restart always -p 5000:5000 --name registry registry:2

step "3/7  Kubernetes (k3s)"
mkdir -p /etc/rancher/k3s
cat > /etc/rancher/k3s/registries.yaml <<'YAML'
mirrors:
  "localhost:5000":
    endpoint:
      - "http://localhost:5000"
YAML
if command -v k3s >/dev/null; then systemctl restart k3s
else curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644; fi
echo "Waiting for the Kubernetes node to be Ready..."
until kubectl get nodes 2>/dev/null | grep -q " Ready"; do sleep 3; done
mkdir -p /home/$U/.kube && cp /etc/rancher/k3s/k3s.yaml /home/$U/.kube/config && chown -R $U:$U /home/$U/.kube

step "4/7  Git server for the project code"
if [ ! -d "$GIT_BARE" ]; then
  mkdir -p /srv/git && git init -q --bare -b main "$GIT_BARE"
  rm -rf "$WORK" && mkdir -p "$WORK"
  (cd "$SRC" && tar --exclude=.git --exclude='*.zip' -cf - .) | (cd "$WORK" && tar -xf -)
  cd "$WORK"
  git init -q -b main
  git config user.name "Sriram R"; git config user.email "sram36505@gmail.com"
  git add -A && git commit -q -m "Initial release: MediCare Patient Portal"
  git tag clean
  git remote add origin "$GIT_BARE" && git push -q origin main --tags
  cd "$SRC"
fi
install -m 755 "$SRC/scripts/post-receive" "$GIT_BARE/hooks/post-receive"
install -m 755 "$SRC/scripts/jenkins-cli" /usr/local/bin/jenkins-cli
install -m 755 "$SRC/scripts/demo.sh" /usr/local/bin/demo

step "5/7  Building the pre-configured Jenkins image (3-5 min)"
docker build -t medicare-jenkins "$SRC/jenkins/image"

step "6/7  Starting Jenkins"
[ -s "$PASS_FILE" ] || openssl rand -hex 6 > "$PASS_FILE"
ADMIN_PASS="$(cat "$PASS_FILE")"
NODE_IP="$(ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')"
docker rm -f jenkins >/dev/null 2>&1 || true
mkdir -p /var/jenkins_home
docker run -d --name jenkins --restart unless-stopped --network host -u root \
  -v /var/jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /etc/rancher/k3s/k3s.yaml:/var/lib/jenkins/.kube/config:ro \
  -v /srv/git:/srv/git \
  -e JENKINS_ADMIN_PASSWORD="$ADMIN_PASS" \
  -e APP_SECRET_KEY="$(openssl rand -hex 32)" \
  -e REPO_URL="file://$GIT_BARE" \
  -e NODE_IP="$NODE_IP" \
  medicare-jenkins >/dev/null
echo "Waiting for Jenkins to start..."
until docker exec jenkins curl -fs -o /dev/null http://localhost:8080/login 2>/dev/null; do sleep 5; done
sleep 15

step "7/7  First run of all 3 pipelines (10-15 min, grab a coffee)"
run() { echo "-> $*"; if jenkins-cli build "$@" -s >/dev/null 2>&1; then echo "   SUCCESS"; else echo "   FAILED - open Jenkins > job > Console Output"; fi; }
run pbl7-cicd
run pbl8-blue-green -p AUTO_APPROVE=true
run pbl8-blue-green -p AUTO_APPROVE=true
run pbl9-devsecops

demo status
