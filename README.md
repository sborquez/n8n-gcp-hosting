# Hosting configuration for n8n

## Setup with Terraform

### Prerequisites

- Terraform
- Google Cloud SDK
- The gke-gcloud-auth-plugin (install the gcloud CLI first)


### Steps

#### 1. Set configuration

```bash
cd infrastructure
cp terraform.tfvars.example terraform.tfvars
code terraform.tfvars
```

#### 2. Initialize Terraform

```bash
terraform init
```

#### 3. Apply the configuration

```bash
terraform apply
```

## Resources

- https://docs.n8n.io/hosting/installation/server-setups/google-cloud/
- https://github.com/n8n-io/n8n-hosting/tree/main