# Live GitHub rulesets

Backups of the two branch rulesets that applied as a union, and the single
ruleset they were folded into. The API is PUT (not PATCH): it replaces `rules`
and `bypass_actors` wholesale. A filter that dropped a rule would loosen `main`
with no warning.

`required_approving_review_count` stays 0.
`strict_required_status_checks_policy` stays true, which was already the
effective value of the union. Turning it off would stop every merge from
making every other open PR `BEHIND`.
