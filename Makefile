PROJECT_ID = $(shell gcloud config get-value project)
REGION = us-central1

REPOSITORY_NAME = n8n-images
N8N_IMAGE_NAME = n8n
# Get latest tag or commit hash if no tags are found
N8N_VERSION = $(shell git describe --tags --abbrev=0 2>/dev/null || git rev-parse --short HEAD || echo "latest")



.PHONY: infra-init infra-plan infra-apply build-and-push

infra-init:
	@echo "Initializing Terraform infrastructure..."
	cd ./infrastructure && \
		terraform init -upgrade

infra-plan:
	@echo "Planning Terraform infrastructure..."
	cd ./infrastructure && \
		terraform init -upgrade && \
		terraform plan -out=tfplan \
			-var="project_id=$(PROJECT_ID)"
	@echo "Terraform plan created: tfplan"
	@echo "Run 'make infra-apply' to apply the changes."

# Apply Terraform infrastructure
infra-apply:
	@echo "Applying Terraform infrastructure..."
	cd ./infrastructure && \
		terraform init -upgrade && \
		terraform apply -auto-approve \
			-var="project_id=$(PROJECT_ID)"

# Cloud Build and push Docker image
build-and-push-n8n:
	@echo "Building and pushing Docker image..."
	gcloud builds submit --region=$(REGION) --config cloudbuild.yaml \
		--substitutions=_PROJECT_ID=$(PROJECT_ID),_REGION=$(REGION),_REPOSITORY_NAME=$(REPOSITORY_NAME),_IMAGE_NAME=$(N8N_IMAGE_NAME),_VERSION=$(N8N_VERSION)