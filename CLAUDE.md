# Agent instructions

This repository is **public**. Anyone can read everything pushed to it: files, commit messages, branch names, PR titles, descriptions and comments. Rewriting history does not remove it, because GitHub keeps old commits and edits reachable.

Commit only material about the images themselves: Dockerfiles, hardening scripts, workflows, tests and their docs. Keep these off GitHub:

- credentials of any kind: tokens, passwords, keys, certificates
- internal hostnames, IP addresses, URLs and local file paths
- names or details of the internal applications and projects that use these images, and their plans, scan reports, logs and test results

Local scan evidence and working notes go in `evidence/`, `*-plan.md` or `*-execution.md`. `.gitignore` excludes them.

Workflows read secrets only from GitHub Actions secrets (`${{ secrets.NAME }}`). Configuration that is not secret, such as `DOCKERHUB_NAMESPACE`, is a repository variable (`${{ vars.NAME }}`). A value stored as the wrong kind reads as empty.

Before pushing, scan the new commits the same way PR CI does:

```sh
gitleaks git --log-opts="origin/main..HEAD" --redact .
```
