# main.tf

# Get the current project details
data "google_project" "project" {}

# Enable Required APIs
locals {
  required_apis = [
    "compute.googleapis.com",
    "secretmanager.googleapis.com"
  ]
}

resource "google_project_service" "project_services_cloudsql" {
  for_each = toset(local.required_apis)
  project = data.google_project.project.number
  service = each.key
  disable_on_destroy = false
}

# IAM Binding for Service Account
resource "google_project_iam_member" "n8n_sql_client" {
  project = var.project_id
  role    = "roles/compute.admin"
  member  = "serviceAccount:${var.service_account_email}"

  depends_on = [
    google_project_service.project_services_cloudsql
  ]
}

# Create a persistent disk for PostgreSQL data
resource "google_compute_disk" "postgres_data_disk" {
  name  = "n8n-db-data-disk"
  type  = "pd-standard"
  size  = 30
  zone  = "${var.region}-a"  # Default to 'a' zone in the selected region
  project = var.project_id

  depends_on = [
    google_project_service.project_services_cloudsql
  ]
}

# Generate random password for PostgreSQL
resource "random_password" "n8n_password" {
  length           = 16
  special          = true
  override_special = "_%@"
}

# Create VM Instance
resource "google_compute_instance" "n8n_instance" {
  name         = "n8n-db"
  machine_type = "e2-micro"
  zone         = "${var.region}-a"  # Default to 'a' zone in the selected region
  project      = var.project_id

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = 10
    }
  }

  attached_disk {
    source      = google_compute_disk.postgres_data_disk.self_link
    device_name = "postgres-data"
  }

  network_interface {
    network = "default"

    # If you need an external IP (generally not recommended for databases)
    # access_config {
    #   // Ephemeral public IP
    # }
  }

  service_account {
    email  = var.service_account_email
    scopes = ["cloud-platform"]
  }

  # Startup script to install and configure PostgreSQL
  metadata_startup_script = <<-EOF
    #!/bin/bash

    # Update and install PostgreSQL
    apt-get update
    apt-get install -y postgresql-13 postgresql-client-13

    # Mount data disk
    mkdir -p /var/lib/postgresql/data
    DISK_NAME=$(ls /dev/disk/by-id/google-* | grep -v "\-part" | head -n 1)
    if ! file -s $DISK_NAME | grep -q filesystem; then
      mkfs.ext4 -m 0 -F -E lazy_itable_init=0,lazy_journal_init=0,discard $DISK_NAME
    fi
    mount -o discard,defaults $DISK_NAME /var/lib/postgresql/data
    chmod 0700 /var/lib/postgresql/data
    chown -R postgres:postgres /var/lib/postgresql/data

    # Add to fstab for auto-mounting on reboot
    echo "$DISK_NAME /var/lib/postgresql/data ext4 discard,defaults 0 2" >> /etc/fstab

    # Stop PostgreSQL service
    systemctl stop postgresql

    # Initialize PostgreSQL data directory
    sudo -u postgres pg_dropcluster --stop 13 main
    sudo -u postgres pg_createcluster 13 main --start -D /var/lib/postgresql/data

    # Configure PostgreSQL to listen on all interfaces
    sudo -u postgres sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /etc/postgresql/13/main/postgresql.conf

    # Add client authentication configuration
    cat > /etc/postgresql/13/main/pg_hba.conf <<EOF_PG_HBA
    local   all             postgres                                peer
    local   all             all                                     md5
    host    all             all             127.0.0.1/32            md5
    host    all             all             ::1/128                 md5
    host    all             all             10.0.0.0/8              md5
    EOF_PG_HBA

    # Restart PostgreSQL
    systemctl restart postgresql

    # Create n8n database and user
    sudo -u postgres psql -c "CREATE USER n8n WITH PASSWORD '${random_password.n8n_password.result}';"
    sudo -u postgres psql -c "CREATE DATABASE n8n;"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE n8n TO n8n;"
    sudo -u postgres psql -c "ALTER USER n8n WITH SUPERUSER;"

    # Enable remote connections
    ufw allow 5432/tcp

    # Create connection information file so we can extract it later
    echo "${google_compute_instance.n8n_instance.name}:5432:n8n:n8n:${random_password.n8n_password.result}" > /root/connection_info
  EOF

  depends_on = [
    google_compute_disk.postgres_data_disk,
    google_project_service.project_services_cloudsql
  ]

  # Allow the instance to be stopped for updates
  allow_stopping_for_update = true
}

# Add a firewall rule for internal PostgreSQL access
resource "google_compute_firewall" "postgres_firewall" {
  name    = "allow-postgres-internal"
  network = "default"
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  # Only allow access from instances in the same network
  source_ranges = ["10.0.0.0/8"]

  depends_on = [
    google_project_service.project_services_cloudsql
  ]
}

# PostgreSQL Database (for compatibility with original module)
resource "google_sql_database" "n8n_db" {
  name     = "n8n"
  instance = "n8n-db"  # This is just a placeholder to maintain compatibility

  # Dummy resource, not actually used
  lifecycle {
    # Prevent actual creation of the resource
    ignore_changes = all
  }

  depends_on = [google_compute_instance.n8n_instance]
}

# Cloud SQL User (for compatibility with original module)
resource "google_sql_user" "n8n_user" {
  name     = "n8n"
  instance = "n8n-db"  # This is just a placeholder to maintain compatibility
  password = random_password.n8n_password.result

  # Dummy resource, not actually used
  lifecycle {
    # Prevent actual creation of the resource
    ignore_changes = all
  }

  depends_on = [google_compute_instance.n8n_instance]
}

# Cloud SQL User Secrets
resource "google_secret_manager_secret" "n8n_db_user" {
  secret_id = "n8n_db_user"
  project   = var.project_id

  replication {
    auto {}
  }

  depends_on = [ google_project_service.project_services_cloudsql ]
}

resource "google_secret_manager_secret_version" "n8n_db_user" {
  secret      = google_secret_manager_secret.n8n_db_user.id
  secret_data = "n8n"

  depends_on = [
    google_secret_manager_secret.n8n_db_user
  ]
}

resource "google_secret_manager_secret_iam_member" "n8n_secret_accessor_sql_user" {
  project = var.project_id
  secret_id = google_secret_manager_secret.n8n_db_user.secret_id
  role = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${var.service_account_email}"

  depends_on = [google_secret_manager_secret.n8n_db_user]
}

resource "google_secret_manager_secret" "n8n_db_password" {
  secret_id = "n8n_db_password"
  project   = var.project_id

  replication {
    auto {}
  }

  depends_on = [ google_project_service.project_services_cloudsql ]
}

# Cloud SQL Password Secrets
resource "google_secret_manager_secret_version" "n8n_db_password" {
  secret      = google_secret_manager_secret.n8n_db_password.id
  secret_data = random_password.n8n_password.result

  depends_on = [
    random_password.n8n_password,
    google_secret_manager_secret.n8n_db_password
  ]
}

resource "google_secret_manager_secret_iam_member" "n8n_secret_accessor_sql_password" {
  project = var.project_id
  secret_id = google_secret_manager_secret.n8n_db_password.secret_id
  role = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${var.service_account_email}"

  depends_on = [google_secret_manager_secret.n8n_db_password]
}

# Store connection name for compatibility with CloudSQL module
resource "google_secret_manager_secret" "n8n_connection_name" {
  secret_id = "n8n_connection_name"
  project   = var.project_id

  replication {
    auto {}
  }

  depends_on = [ google_project_service.project_services_cloudsql ]
}

resource "google_secret_manager_secret_version" "n8n_connection_name" {
  secret      = google_secret_manager_secret.n8n_connection_name.id
  secret_data = "${var.project_id}:${var.region}:n8n-db" # Mimics CloudSQL connection name format

  depends_on = [
    google_compute_instance.n8n_instance,
    google_secret_manager_secret.n8n_connection_name
  ]
}