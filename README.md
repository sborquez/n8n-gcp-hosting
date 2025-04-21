# Hosting configuration for n8n

## Setup server

```
make infra-apply
```

## Next steps
- [x] Mount n8n in Cloud Run with Cloud SQL
- [x] Add persistent storage to n8n with Cloud Storage
- [x] Protect SQL password with Secret Manager
- [x] Trim down Service Account permissions
- [x] Add Cloud Build step instead of build locally
- [x] Write Custom node
- [ ] Add support for alternative DB (free Supabase DB)
- [ ] Add Custom node to n8n (hosted)
- [ ] Protect n8n with Cloud IAP? (check IAP for Cloud Run)
- [ ] Add SA to n8n (hosted)

## Resources

- https://docs.n8n.io/hosting/installation/docker/
- https://docs.n8n.io/hosting/installation/server-setups/google-cloud/
- https://github.com/n8n-io/n8n-hosting/tree/main

## Issues:

```
There was a problem loading init data:
Credentials could not be decrypted. The likely reason is that a different "encryptionKey" was used to encrypt the data.
```