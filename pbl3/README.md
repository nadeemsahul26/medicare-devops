# MediCare Patient Portal: DevOps PBL-III (PBL 7, 8 and 9)

One healthcare web app, three Jenkins pipelines, one server, one setup command.

| PBL | Task | Pipeline | App link |
|---|---|---|---|
| 7 | CI/CD pipeline to deploy a Dockerized app on Kubernetes using Jenkins | `jenkins/Jenkinsfile.pbl7` | `http://<IP>:30007` |
| 8 | Automated Blue-Green deployment using Jenkins, Kubernetes, Docker | `jenkins/Jenkinsfile.pbl8` | live `:30008`, preview `:30018` |
| 9 | DevSecOps implementation in a healthcare system | `jenkins/Jenkinsfile.pbl9` | `http://<IP>:30009` |

The app's top banner shows **version, blue/green colour, pod name** and a yellow **"What's new"** line, so every deployment is visible in the browser.

```
 git push ──► Git server ──(post-receive hook = webhook)──► Jenkins
                                                              │ test → build → [security gates] → push
                                                              ▼
                                               Private Docker registry (localhost:5000)
                                                              │ kubectl
                                                              ▼
                       k3s Kubernetes:  pbl7 (rolling) │ pbl8 (blue + green) │ pbl9 (hardened)
                                                              │
                                                       Browser (NodePort)
```

---

## Setup (about 25 minutes, mostly waiting)

**1. Upload the zip to GitHub.** On your repo page: **Add file → Upload files** → drag in **`pbl3.zip`** (the zip itself) → **Commit changes**.

**2. Launch an EC2 server.** Ubuntu 24.04 · **t3.large** · **30 GB** disk · security group open on ports **22, 8080, 30007, 30008, 30018, 30009**.

**3. Paste one command.** EC2 → your instance → **Connect → EC2 Instance Connect → Connect**:
```bash
git clone https://github.com/sriram36505/medicare-devops.git && cd medicare-devops && unzip -oq pbl3.zip && sudo bash pbl3/scripts/setup.sh
```
When it finishes, it prints your Jenkins login and all the links. All 3 pipelines have already run once. If anything says FAILED, run the same command again (it's safe to repeat).

Lost the links? Run `sudo demo status`.

**Stop the instance** after every session (EC2 → Instance state → Stop), because it's billed per hour. When you **Start** it again, everything comes back by itself. Run `sudo demo status` to get the new IP.

---

## Demo commands (run in the EC2 terminal)

Keep two browser tabs open: **Jenkins** and the **app**.

### PBL 7: CI/CD to Kubernetes
| Command | What the examiner sees |
|---|---|
| `sudo demo pbl7` | `git push` → hook triggers Jenkins → Test → Build → Push → Deploy → Smoke test. The terminal shows pods being replaced one by one (zero downtime). Refresh `:30007`: new version number and new "What's new" text |
| `sudo demo badcode` | A buggy commit. The pipeline **stops at Unit Tests**, nothing is deployed, and the site stays up |
| `sudo demo fix` | Fixes it, and the pipeline goes green again |

### PBL 8: Blue-Green
| Command | What the examiner sees |
|---|---|
| `sudo demo pbl8` | The new version goes to the **idle** colour. Preview `:30018` shows the new version while live `:30008` is still the old one. Jenkins waits; click **Switch traffic**. Refresh live: the colour flips with no downtime |
| `sudo demo rollback` | Live traffic flips back to the previous colour in seconds, with no rebuild |

### PBL 9: DevSecOps (healthcare)
| Command | What the examiner sees |
|---|---|
| `sudo demo pbl9` | A release passes every gate: Gitleaks → Bandit → pip-audit → Tests → Trivy image → Trivy K8s config → Deploy → OWASP ZAP. The reports are under **Build → Artifacts** |
| `sudo demo leak` | Commits a fake token, and the build is **blocked at Secrets Scan** |
| `sudo demo insecure` | Commits `eval()` code, and the build is **blocked at SAST (Bandit B307)** |
| `sudo demo privileged` | A privileged pod is **rejected** by the *restricted* Pod Security Standard |
| `sudo demo fix` | Removes the bad commits, and everything goes green |

Also show `http://<IP>:30009/patients`: names and phone numbers are masked.

**PBL 9 controls (put this table on a slide):**
| Risk in healthcare | Control | Tool |
|---|---|---|
| Passwords/keys committed to Git | Secrets scanning | Gitleaks |
| Injection / unsafe code | SAST | Bandit |
| Vulnerable libraries | SCA | pip-audit |
| Vulnerable OS packages in image | Container scan | Trivy image |
| Misconfigured K8s (root, privileged) | IaC scan + Pod Security Standards | Trivy config, PSA `restricted` |
| Secret exposure | K8s Secret from Jenkins credential store | Jenkins Credentials, K8s Secret |
| Lateral movement after breach | Network segmentation | NetworkPolicy |
| Runtime web vulnerabilities | DAST | OWASP ZAP baseline |
| Patient data exposure (HIPAA, India DPDP Act 2023) | PII masking, audit logs, least privilege | App code, ServiceAccount with no token |

---

## Presentation outline (3 marks each). Reuse slides 1–2 across all three.

**PBL 7:** 1 Title · 2 Problem (manual deployment is slow and error-prone) · 3 Architecture diagram · 4 Tools and why · 5 Jenkinsfile stages (stage-view screenshot) · 6 Rolling update and probes · 7 Demo screenshots before/after + rollback · 8 Conclusion
**PBL 8:** 1 Title · 2 Why downtime and risky releases matter · 3 Blue-Green concept diagram (two environments, one router) · 4 How K8s does it: labels + Service selector · 5 Pipeline flow with preview test and approval gate · 6 Demo: blue → green → rollback · 7 Pros/cons vs rolling and canary · 8 Conclusion
**PBL 9:** 1 Title · 2 Why healthcare needs security (patient data, HIPAA / DPDP) · 3 DevSecOps = shift-left · 4 Pipeline with security gates · 5 Controls-to-risks table (above) · 6 K8s hardening · 7 Demo: blocked secret + blocked eval + rejected privileged pod · 8 Reports + conclusion

## Viva questions (2 marks each). Short answers.

**PBL 7**
- *CI vs CD?* CI = automatically build and test every commit. CD = automatically release the tested build to an environment.
- *How does a git push trigger Jenkins?* Our Git server has a **post-receive hook** (`scripts/post-receive`). It works like a GitHub webhook: on every push it calls Jenkins, and the tag in the commit message (`[pbl7]`, `[pbl8]`, `[pbl9]`) picks which pipeline runs.
- *How was Jenkins configured?* As code (JCasC + Job DSL in `jenkins/image/`): plugins, users, credentials and jobs are all in Git, so it's reproducible with no manual clicks.
- *Why does the image scan only block CRITICAL?* Every HIGH and CRITICAL finding is reported, but only CRITICAL ones stop a release. That's a common, practical policy: otherwise a single unfixable base-image issue would block every deployment.
- *Declarative vs scripted pipeline?* Declarative uses a fixed `pipeline { stages {} }` structure and is easier to read. Scripted is plain Groovy code and more flexible.
- *Image vs container?* An image is a read-only template. A container is a running instance of that image.
- *Pod vs Deployment vs Service?* A Pod runs containers. A Deployment manages replicas and updates of pods. A Service gives a stable IP/port and load-balances to pods by label.
- *How is downtime avoided?* RollingUpdate with `maxUnavailable: 0`, plus a readinessProbe, so a pod gets traffic only once it's healthy.
- *Why a private registry?* Images stay inside our server, with no public exposure of healthcare app images and no Docker Hub rate limits. In a company this would be AWS ECR.
- *Why tag images with the build number, not `latest`?* Every build is traceable, and you can roll back to an exact version.

**PBL 8**
- *Blue-green vs rolling vs canary?* Blue-green switches all traffic at once between two full environments. Rolling replaces pods gradually. Canary sends a small % of traffic to the new version first.
- *How is traffic switched?* By patching the Service's `selector.version` from blue to green. It takes effect almost instantly.
- *Rollback time?* About 1 second, because the old colour is still running.
- *Disadvantage?* It needs double the resources during a release. Database schema changes must also be backward-compatible, because both versions share one database.
- *Why a preview Service?* To test the new version on real infrastructure before any user sees it.

**PBL 9**
- *What is DevSecOps / shift-left?* Security checks are built into the pipeline from the first commit, instead of a security review at the end.
- *SAST vs DAST vs SCA?* SAST reads source code. DAST attacks the running app. SCA checks third-party libraries for known CVEs.
- *Why fail the build on HIGH/CRITICAL?* Policy as code: insecure builds can't reach production, so no human has to remember to check.
- *How are secrets handled?* They live in the Jenkins credential store and are injected as a K8s Secret at deploy time. They are never in Git, and Gitleaks blocks accidental commits.
- *Why non-root + read-only filesystem?* If the app is compromised, the attacker can't install tools or escalate privileges.
- *What does the NetworkPolicy do?* Only port 5000 is allowed in and only DNS out, which limits lateral movement.
- *Healthcare regulations?* HIPAA (US) and India's DPDP Act 2023 require protecting personal health data. Our controls: masking, least privilege, audit logs, encryption of secrets.

---

## Troubleshooting
| Symptom | Fix |
|---|---|
| Setup stopped or a step says FAILED | Run the same setup command again: `cd ~/medicare-devops && sudo bash pbl3/scripts/setup.sh` |
| `unzip: cannot find pbl3.zip` | The zip isn't in the GitHub repo yet, or GitHub renamed it. Check the file name on GitHub and use that name |
| Jenkins page not opening | Port 8080 missing in the security group, or Jenkins still starting: `sudo docker logs -f jenkins` |
| App link not opening | Port 30007/30008/30018/30009 missing in the security group |
| Pods `ImagePullBackOff` | `sudo docker start registry` then run the pipeline again |
| `kubectl: connection refused` | `sudo systemctl restart k3s`, wait 30 s |
| PBL 8 build waiting forever | It's waiting for you: open the build in Jenkins → **Switch traffic** (or Abort) |
| Server slow during PBL 9 | Use t3.large; `sudo docker system prune -af` between practice runs |

Run the app locally without Docker: `pip install -r app/requirements.txt && python app/app.py` → http://127.0.0.1:5000
