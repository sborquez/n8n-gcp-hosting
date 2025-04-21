PROJECT_ID = $(shell gcloud config get-value project)
REGION = us-central1

N8N_IMAGE_REPO = n8n-images
N8N_IMAGE_NAME = n8n
N8N_TAG = latest
N8N_IMAGE = "$(REGION)-docker.pkg.dev/$(PROJECT_ID)/$(N8N_IMAGE_REPO)/$(N8N_IMAGE_NAME):$(N8N_TAG)"


.PHONY: infra-apply push-local build-and-push

# Apply Terraform infrastructure
infra-apply:
	@echo "Applying Terraform infrastructure..."
	cd ./infrastructure && \
		terraform init -upgrade && \
		terraform apply -auto-approve \
			-var="project_id=$(PROJECT_ID)"

# Cloud Build and push Docker image
build-and-push:
	@echo "Building and pushing Docker image..."
	gcloud builds submit --region=$(REGION) --config cloudbuild.yaml \
		--substitutions=_IMAGE_NAME=$(N8N_IMAGE)