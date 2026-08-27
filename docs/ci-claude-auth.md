# The CI agent's credentials

`.github/workflows/claude.yml` runs Claude Code on CI (ADR 0012). It holds no credential of
its own. Each run mints one: GitHub issues an OIDC token for the job, AWS exchanges it for a
session on a role that trusts only this repository, and the Anthropic key is read from
Secrets Manager with that session. The session expires with the job, and GitHub stores two
variables -- a role ARN and a secret name -- neither of which is a credential.

Anthropic's API does not exchange an OIDC token for a key, so the key itself is long-lived.
What federation buys is where it lives: in one AWS secret with rotation and CloudTrail,
never in GitHub, and reachable only by a job on this repository.

Run these once, in an AWS account you own. `docs/redaction.md` applies: the account id is
not written into this repo.

## 1. Trust GitHub's OIDC provider

Skip if the account already has it -- one provider serves every repository.

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com
```

## 2. A role this repository alone can assume

`sub` is the claim that scopes it. `repo:zaffnet/whetstone:*` covers every branch and PR of
this repo and nothing else; narrow it to `repo:zaffnet/whetstone:ref:refs/heads/main` if you
would rather the agent only ran from `main`. `aud` must be `sts.amazonaws.com`, which is what
`configure-aws-credentials` requests.

```bash
account=$(aws sts get-caller-identity --query Account --output text)
cat >/tmp/trust.json <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::${account}:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:zaffnet/whetstone:*"
      }
    }
  }]
}
JSON

aws iam create-role \
  --role-name whetstone-ci-agent \
  --description "Claude Code on CI for zaffnet/whetstone" \
  --max-session-duration 3600 \
  --assume-role-policy-document file:///tmp/trust.json
```

Both conditions matter. Without the `aud` check any GitHub workflow anywhere could present a
token; without the `sub` check any repository could.

## 3. The key, and permission to read exactly it

```bash
aws secretsmanager create-secret \
  --name whetstone/anthropic-api-key \
  --description "Anthropic API key for the CI agent" \
  --secret-string "sk-ant-..."   # from console.anthropic.com, scoped to its own workspace

secret_arn=$(aws secretsmanager describe-secret \
  --secret-id whetstone/anthropic-api-key --query ARN --output text)

cat >/tmp/read-key.json <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "secretsmanager:GetSecretValue",
    "Resource": "${secret_arn}"
  }]
}
JSON

aws iam put-role-policy \
  --role-name whetstone-ci-agent \
  --policy-name read-anthropic-key \
  --policy-document file:///tmp/read-key.json
```

One secret ARN, one action. The role can read that key and nothing else in the account.

## 4. Tell the workflow where to look

```bash
gh variable set CI_AGENT_ROLE_ARN --body "$(aws iam get-role \
  --role-name whetstone-ci-agent --query Role.Arn --output text)"
gh variable set ANTHROPIC_KEY_SECRET_ID --body whetstone/anthropic-api-key
gh variable set AWS_REGION --body us-east-1   # optional; the workflow defaults to us-east-1
```

Variables, not secrets. A role ARN and a secret name are not credentials, and leaving them
visible is what makes the workflow's skip notice tell you which one is missing. Until both
exist the job skips with a notice instead of failing.

## Checking it

Comment `@claude` on any pull request. The run should show `configure-aws-credentials`
assuming `whetstone-ci-agent`, then the agent working. A failure at the assume-role step is
almost always the `sub` condition: the run's own value is printed in the error, and it must
match the pattern in the trust policy.

Nothing above is stored on a developer machine, so rotating the key is
`aws secretsmanager put-secret-value` and nothing else. Revoking CI's access entirely is
`aws iam delete-role-policy`.
