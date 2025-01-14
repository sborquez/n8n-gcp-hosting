resource "kubernetes_namespace" "n8n" {
  metadata {
    name = "n8n"
  }
}

resource "kubernetes_storage_class" "regional" {
  metadata {
    name = "regionalpd-storageclass"
  }

  storage_provisioner = "kubernetes.io/gce-pd"
  parameters = {
    type             = "pd-standard"
    replication-type = "regional-pd"
  }

  allowed_topologies {
    match_label_expressions {
      key = "failure-domain.beta.kubernetes.io/zone"
      values = var.storage_class_zones
    }
  }
}

resource "kubernetes_persistent_volume_claim" "postgres" {
  metadata {
    name      = "postgresql-pv"
    namespace = kubernetes_namespace.n8n.metadata[0].name
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    storage_class_name = kubernetes_storage_class.regional.metadata[0].name

    resources {
      requests = {
        storage = "300Gi"  # Adjust size as needed
      }
    }
  }
}

resource "kubernetes_config_map" "postgres_init" {
  metadata {
    name      = "init-data"
    namespace = kubernetes_namespace.n8n.metadata[0].name
  }

  data = {
    "init-data.sh" = <<-EOF
      #!/bin/bash
      set -e
      psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
          CREATE USER $POSTGRES_NON_ROOT_USER WITH PASSWORD '$POSTGRES_NON_ROOT_PASSWORD';
          GRANT ALL PRIVILEGES ON DATABASE $POSTGRES_DB TO $POSTGRES_NON_ROOT_USER;
      EOSQL
    EOF
  }
}

resource "kubernetes_secret" "postgres" {
  metadata {
    name      = "postgres-secret"
    namespace = kubernetes_namespace.n8n.metadata[0].name
  }

  type = "Opaque"

  data = {
    POSTGRES_USER     = var.postgres_user
    POSTGRES_PASSWORD = var.postgres_password
    POSTGRES_DB       = var.postgres_db
    POSTGRES_NON_ROOT_USER = var.postgres_user
    POSTGRES_NON_ROOT_PASSWORD = var.postgres_password
  }
}

resource "kubernetes_deployment" "postgres" {
  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace.n8n.metadata[0].name
    labels = {
      service = "postgres-n8n"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        service = "postgres-n8n"
      }
    }

    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_surge       = 1
        max_unavailable = 1
      }
    }

    template {
      metadata {
        labels = {
          service = "postgres-n8n"
        }
      }

      spec {
        container {
          name  = "postgres"
          image = "postgres:13"

          resources {
            limits = {
              cpu    = "4"
              memory = "4Gi"
            }
            requests = {
              cpu    = "1"
              memory = "2Gi"
            }
          }

          port {
            container_port = 5432
          }

          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }

          env {
            name = "POSTGRES_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgres.metadata[0].name
                key  = "POSTGRES_USER"
              }
            }
          }

          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgres.metadata[0].name
                key  = "POSTGRES_PASSWORD"
              }
            }
          }

          env {
            name  = "POSTGRES_DB"
            value = var.postgres_db
          }

          env {
            name = "POSTGRES_NON_ROOT_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgres.metadata[0].name
                key  = "POSTGRES_NON_ROOT_USER"
              }
            }
          }

          env {
            name = "POSTGRES_NON_ROOT_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgres.metadata[0].name
                key  = "POSTGRES_NON_ROOT_PASSWORD"
              }
            }
          }

          env {
            name  = "POSTGRES_HOST"
            value = "postgres-service"
          }

          env {
            name  = "POSTGRES_PORT"
            value = "5432"
          }

          volume_mount {
            name       = "postgresql-pv"
            mount_path = "/var/lib/postgresql/data"
          }

          volume_mount {
            name       = "init-data"
            mount_path = "/docker-entrypoint-initdb.d/init-n8n-user.sh"
            sub_path   = "init-data.sh"
          }
        }

        volume {
          name = "postgresql-pv"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.postgres.metadata[0].name
          }
        }

        volume {
          name = "postgres-secret"
          secret {
            secret_name = kubernetes_secret.postgres.metadata[0].name
          }
        }

        volume {
          name = "init-data"
          config_map {
            name = kubernetes_config_map.postgres_init.metadata[0].name
            default_mode = "0744"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "postgres" {
  metadata {
    name      = "postgres-service"
    namespace = kubernetes_namespace.n8n.metadata[0].name
    labels = {
      service = "postgres-n8n"
    }
  }

  spec {
    cluster_ip = "None"  # This makes it a headless service

    port {
      name        = "5432"
      port        = 5432
      target_port = 5432
      protocol    = "TCP"
    }

    selector = {
      service = "postgres-n8n"
    }
  }
}

resource "kubernetes_persistent_volume_claim" "n8n" {
  metadata {
    name      = "n8n-claim0"
    namespace = kubernetes_namespace.n8n.metadata[0].name
    labels = {
      service = "n8n-claim0"
    }
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "2Gi"
      }
    }
  }
}

resource "kubernetes_secret" "n8n" {
  metadata {
    name      = "n8n-secret"
    namespace = kubernetes_namespace.n8n.metadata[0].name
  }

  data = {
    N8N_ENCRYPTION_KEY = var.n8n_encryption_key
    DB_TYPE           = "postgresdb"
    DB_POSTGRESDB_HOST = "postgres"
    DB_POSTGRESDB_PORT = "5432"
    DB_POSTGRESDB_USER = var.postgres_user
    DB_POSTGRESDB_PASS = var.postgres_password
    DB_POSTGRESDB_DATABASE = var.postgres_db
  }
}

resource "kubernetes_deployment" "n8n" {
  metadata {
    name      = "n8n"
    namespace = kubernetes_namespace.n8n.metadata[0].name
    labels = {
      service = "n8n"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        service = "n8n"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          service = "n8n"
        }
      }

      spec {
        init_container {
          name  = "volume-permissions"
          image = "busybox:1.36"

          command = ["sh", "-c", "chown 1000:1000 /data"]

          volume_mount {
            name       = "n8n-claim0"
            mount_path = "/data"
          }
        }

        container {
          name    = "n8n"
          image   = "n8nio/n8n"
          command = ["/bin/sh"]
          args    = ["-c", "sleep 5; n8n start"]

          env {
            name  = "DB_TYPE"
            value = "postgresdb"
          }

          env {
            name  = "DB_POSTGRESDB_HOST"
            value = "postgres-service.n8n.svc.cluster.local"
          }

          env {
            name  = "DB_POSTGRESDB_PORT"
            value = "5432"
          }

          env {
            name  = "DB_POSTGRESDB_DATABASE"
            value = "n8n"
          }

          env {
            name = "DB_POSTGRESDB_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgres.metadata[0].name
                key  = "POSTGRES_NON_ROOT_USER"
              }
            }
          }

          env {
            name = "DB_POSTGRESDB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgres.metadata[0].name
                key  = "POSTGRES_NON_ROOT_PASSWORD"
              }
            }
          }

          env {
            name  = "N8N_PROTOCOL"
            value = "http"
          }

          env {
            name  = "N8N_PORT"
            value = "5678"
          }

          resources {
            requests = {
              memory = "250Mi"
            }
            limits = {
              memory = "500Mi"
            }
          }

          port {
            container_port = 5678
          }

          volume_mount {
            name       = "n8n-claim0"
            mount_path = "/home/node/.n8n"
          }
        }

        volume {
          name = "n8n-claim0"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.n8n.metadata[0].name
          }
        }

        volume {
          name = "n8n-secret"
          secret {
            secret_name = kubernetes_secret.n8n.metadata[0].name
          }
        }

        volume {
          name = "postgres-secret"
          secret {
            secret_name = kubernetes_secret.postgres.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "n8n" {
  metadata {
    name      = "n8n"
    namespace = kubernetes_namespace.n8n.metadata[0].name
    labels = {
      service = "n8n"
    }
  }

  spec {
    type = "LoadBalancer"

    port {
      name        = "5678"
      port        = 5678
      target_port = 5678
      protocol    = "TCP"
    }

    selector = {
      service = "n8n"
    }
  }
}
