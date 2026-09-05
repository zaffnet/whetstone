# Skills

Every agent skill this repo writes or installs, in one place. Three install paths:

- `skills/` holds the hand-written skills. `home/.chezmoiscripts/run_onchange_after_25-link-skills.sh.tmpl`
  symlinks each one into `~/.agents/skills`, which Claude Code, Cursor, and Kiro read.
  `npx skills add zaffnet/whetstone` and the `whetstone-skills` plugin install the same set.
- `home/dot_agents/skills.txt` lists third-party skills.
  `home/.chezmoiscripts/run_onchange_after_30-agent-skills.sh.tmpl` installs them with
  `npx skills add -g`.
- Plugins carry skills of their own. Claude Code enables them in
  `home/.chezmoitemplates/claude-settings.json` (`enabledPlugins`) and Codex in
  `home/.chezmoitemplates/codex-config.toml.tmpl` (`[plugins.*]`);
  `home/dot_agents/plugins/desired.yaml` is the inventory kept in step with both.

Keep this file in step with all three when a skill is added or removed. The first two tables
are checked against their sources by `tools/check-skills-doc.py`, which pre-commit runs. The
plugin table is not: a plugin whose skill set is versioned upstream is named below, not
enumerated, so there is no file here to compare it against.

## Written here

Source: `skills/<name>/SKILL.md`.

| Skill | What it does |
| --- | --- |
| `address-pr-comments-sequential` | Works through unresolved PR review comments one at a time. |
| `align-docs-with-code` | Fans subagents across the code and the docs, fixes what the docs get wrong, opens a PR. |
| `deep-claude-code-review` | Claude-only deep review: several Claude subagents review the same change, findings merged by agreement. |
| `deep-pr-review` | Multi-model deep review: one reviewer per model you can reach, findings merged by agreement. |
| `deslop` | Strips AI slop and off-style code from the branch diff. |
| `prose-honesty` | Judges every sentence an agent writes against what a later reader needs. |
| `simplify-english` | Rewrites Markdown prose into plain English, structure intact. |
| `sync-machine-config-to-repo` | Scans the machine for configs and packages whetstone does not manage, then adds the worthwhile ones on a branch. |
| `teach-me` | Teaches a topic one chunk at a time, quizzing between chunks. |
| `writing-whip` | Kills AI writing tropes at generation time. |

## Installed from elsewhere

Source: `home/dot_agents/skills.txt`.

From `aws/agent-toolkit-for-aws`:

| Skill | What it does |
| --- | --- |
| `amazon-bedrock` | Model invocation, Knowledge Bases, Agents, Guardrails, AgentCore. |
| `aws-auth` | Cognito user pools, sign-in flows, OAuth, JWT authorizers. |
| `aws-billing-and-cost-management` | Cost analysis, budgets, Savings Plans, right-sizing. |
| `aws-blocks` | Full-stack apps with the AWS Blocks infrastructure-from-code framework. |
| `aws-cdk` | CDK stacks and constructs in TypeScript or Python. |
| `aws-cloudformation` | Template authoring, validation, failed-stack diagnosis. |
| `aws-compute` | EC2 instances, launch templates, Auto Scaling, SSM fleet ops. |
| `aws-containers` | ECS, Fargate, ECR: task definitions, services, deployments. |
| `aws-database` | Routes a database question to the right AWS database service. |
| `aws-deployment` | CodePipeline, CodeBuild, CodeDeploy, CodeArtifact, source connections. |
| `aws-iam` | Roles, trust policies, condition operators, policy generation. |
| `aws-messaging-and-streaming` | SQS, SNS, EventBridge, Kinesis, MSK, MQ patterns. |
| `aws-networking` | Routes to Route 53, CloudFront, Transit Gateway, VPN, WAF, Shield. |
| `aws-observability` | CloudWatch, X-Ray, CloudTrail, ADOT, Application Signals. |
| `aws-sdk-js-v3-usage` | `@aws-sdk/*` patterns for JavaScript and TypeScript. |
| `aws-sdk-python-usage` | boto3 and botocore patterns: clients, errors, paginators. |
| `aws-sdk-swift-usage` | aws-sdk-swift patterns. |
| `aws-security` | Security Hub, GuardDuty, Inspector, Macie, Detective, Security Lake. |
| `aws-serverless` | Lambda, API Gateway, Step Functions, EventBridge, SAM. |
| `creating-secrets-using-best-practices` | Secrets Manager secrets with KMS, rotation, least privilege. |
| `launch-with-aws` | Migrates a vibe-coded or frontend web app to AWS. |
| `querying-aws-cloudwatch` | SQL over CloudWatch logs exported to S3 Tables. |
| `querying-aws-s3` | S3 Metadata and Storage Lens tables via Athena SQL. |
| `rds-oss` | RDS MySQL, MariaDB, PostgreSQL: creation, upgrades, Blue/Green. |
| `route53` | DNS records, routing policies, health checks, Resolver, DNS Firewall. |
| `routing-traffic-with-route53-and-cloudfront` | Points a custom domain at a CloudFront distribution. |
| `setting-up-cloudwatch-alarm-notifications` | SNS topics and subscriptions for alarm notifications. |
| `signing-in-to-aws` | Gets local CLI and SDK credentials with `aws login`. |
| `troubleshooting-application-failures` | Diagnoses failures from CloudWatch log groups. |

From other repos:

| Skill | Source repo | What it does |
| --- | --- | --- |
| `fastapi` | `fastapi/fastapi` | FastAPI and Pydantic conventions for new and existing code. |
| `sqlmodel` | `fastapi/sqlmodel` | SQLModel patterns: models, sessions, queries, relationships, FastAPI integration. |
| `verification-before-completion` | `obra/superpowers` | Demands command output before any claim that work passes. |
| `gh-stack` | `github/gh-stack` | Stacked PRs: create, push, submit, sync, rebase, merge. |
| `find-skills` | `vercel-labs/skills` | Finds and installs skills for a described task. |
| `writing-clearly-and-concisely` | `obra/the-elements-of-style` | Strunk's rules applied to any prose. |
| `discernment-nudge` | `anthropics/skills` | Appends 2-3 questions that help the reader check a substantive answer. |

## From plugins

Source: the `enabledPlugins` and `[plugins.*]` entries above.

| Skill | Plugin | Products | What it does |
| --- | --- | --- | --- |
| `claude-md-improver` | `claude-md-management@claude-plugins-official` | Codex | Audits and improves a repo's `CLAUDE.md` files. The plugin is off in Claude Code, which had no recorded usage of it. |
| its own set, versioned upstream | `superpowers@claude-plugins-official` (`obra/superpowers`) | Codex | Not enumerated here; read the plugin's own `skills/`. `verification-before-completion` is also in `skills.txt`, so Codex sees it twice; Claude Code, where the plugin is off, gets it only from `skills.txt`. |
