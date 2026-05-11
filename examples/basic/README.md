# basic

Minimal example: the module takes no inputs and just creates the IAM
resources. An external orchestrator reads the outputs and posts them to
the Salt backend.

```sh
export IC_API_KEY='your-ibm-cloud-api-key'

terraform init
terraform apply

# Hand the API key to your orchestration:
terraform output -raw api_key
```