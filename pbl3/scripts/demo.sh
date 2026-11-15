#!/usr/bin/env bash
# One-word demo commands for PBL 7, 8 and 9.  Usage:  sudo demo <command>
set -uo pipefail
WORK=/opt/medicare-work
[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"

pub_ip() {
  local t; t=$(curl -s -m 2 -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 60" || true)
  curl -s -m 2 -H "X-aws-ec2-metadata-token: $t" http://169.254.169.254/latest/meta-data/public-ipv4 || echo "<EC2-PUBLIC-IP>"
}
release() {   # release "<tag>" "<what's new>"
  cd "$WORK"
  echo "$2" > app/release.txt
  git add -A
  git commit -q -m "$1 $2"
  echo ">>> git push   (commit: $1 $2)"
  git push origin main 2>&1 | sed 's/^remote: //'
}
say() { echo; echo "  $*"; }

IP=$(pub_ip)
case "${1:-help}" in
  status)
    PASS=$(cat /root/jenkins-admin-password.txt)
    LIVE=$(kubectl -n pbl8 get svc medicare -o jsonpath='{.spec.selector.version}' 2>/dev/null)
    cat <<MSG

 ==================== MediCare DevOps PBL-III ====================
  Jenkins : http://$IP:8080         user: admin   password: $PASS
  PBL 7   : http://$IP:30007        (CI/CD + rolling update)
  PBL 8   : http://$IP:30008  live = ${LIVE:-?}     preview: http://$IP:30018
  PBL 9   : http://$IP:30009        (DevSecOps, hardened)
 ================================================================
MSG
    kubectl get pods -n pbl7 -o wide 2>/dev/null | head -5
    kubectl get pods -n pbl8 -l app=medicare 2>/dev/null
    kubectl get pods -n pbl9 2>/dev/null ;;

  pbl7)
    release "[pbl7]" "Release $(date +%H:%M) - Vitals Checker now flags pre-diabetic sugar levels"
    say "Jenkins job pbl7-cicd started. Open http://$IP:8080/job/pbl7-cicd/"
    say "Watching the rolling update (Ctrl+C to stop watching):"
    sleep 25; timeout 150 kubectl -n pbl7 get pods -w ;;

  badcode)
    cd "$WORK"
    sed -i 's/status="UP"/status="DOWN"/' app/app.py
    git commit -qam "[pbl7] Buggy change: health endpoint broken"
    git push origin main 2>&1 | sed 's/^remote: //'
    say "Pipeline will FAIL at 'Unit Tests' -> nothing is deployed, the live site stays healthy."
    say "Afterwards run:  sudo demo fix" ;;

  pbl8)
    release "[pbl8]" "Release $(date +%H:%M) - new Patient Directory layout"
    say "pbl8-blue-green is deploying to the IDLE colour. Live users are untouched."
    say "1) Open the PREVIEW  http://$IP:30018  -> new version"
    say "2) Live is still old  http://$IP:30008"
    say "3) In Jenkins click 'Switch traffic': http://$IP:8080/job/pbl8-blue-green/" ;;

  rollback)
    jenkins-cli build pbl8-blue-green -p ACTION=rollback >/dev/null
    say "Rollback started - live traffic flips back to the previous colour in a few seconds."
    say "Refresh http://$IP:30008" ;;

  pbl9)
    release "[pbl9]" "Release $(date +%H:%M) - security-hardened build"
    say "Watch all security gates: http://$IP:8080/job/pbl9-devsecops/" ;;

  leak)
    cd "$WORK"
    echo "GITHUB_TOKEN = \"ghp_$(head -c 500 /dev/urandom | tr -dc A-Za-z0-9 | head -c 36)\"  # fake token for demo" > app/leaked_config.py
    git add -A && git commit -qm "[pbl9] Developer accidentally commits a token"
    git push origin main 2>&1 | sed 's/^remote: //'
    say "Pipeline will be BLOCKED at 'Secrets Scan (Gitleaks)'. Then run:  sudo demo fix" ;;

  insecure)
    cd "$WORK"
    cat >> app/app.py <<'PY'


@app.route("/calc")
def calc():
    return str(eval(request.args.get("q", "1+1")))
PY
    git commit -qam "[pbl9] Developer adds an unsafe eval() endpoint"
    git push origin main 2>&1 | sed 's/^remote: //'
    say "Pipeline will be BLOCKED at 'SAST (Bandit)' - B307 use of eval. Then run:  sudo demo fix" ;;

  privileged)
    say "Trying to start a PRIVILEGED pod in the healthcare namespace (pbl9):"
    kubectl -n pbl9 run attacker --image=nginx --privileged --restart=Never 2>&1 | sed 's/^/    /'
    say "Rejected by the 'restricted' Pod Security Standard."
    say "Same image in a normal namespace would be allowed - the policy is what protects patient data." ;;

  fix)
    cd "$WORK"
    git checkout clean -- app/app.py
    rm -f app/leaked_config.py
    git add -A
    git commit -qm "[pbl7] [pbl9] Fix: remove leaked token, unsafe code, broken health check"
    git push origin main 2>&1 | sed 's/^remote: //'
    say "Fixed. All three pipelines run again and go green." ;;

  *)
    cat <<'HELP'
Usage: sudo demo <command>

  status       show all links, Jenkins password and running pods
  PBL 7  pbl7        push a new release -> CI/CD -> zero-downtime rolling update
         badcode     push a bug -> unit tests stop the pipeline (nothing deployed)
  PBL 8  pbl8        push a release -> goes to idle colour -> you click 'Switch traffic'
         rollback    instantly switch live traffic back to the previous colour
  PBL 9  pbl9        push a release through all security gates
         leak        commit a fake token -> blocked by Gitleaks
         insecure    commit eval() code -> blocked by Bandit (SAST)
         privileged  try a privileged pod -> rejected by Pod Security Standards
  fix          undo badcode / leak / insecure
HELP
    ;;
esac
