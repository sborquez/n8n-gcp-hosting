# Hosting configuration for n8n

## Setup server

```
make infra-apply
```

## Next steps
- [x] Mount n8n in Cloud Run with Cloud SQL
- [x] Add persistent storage to n8n with Cloud Storage
- [ ] Solve problem with credentials "encryptionKey"
- [ ] Protect SQL password with Secret Manager
- [ ] Add Cloud Build step instead of build locally
- [ ] Add Custom node to n8n
- [ ] Trim down Service Account permissions
- [ ] Protect n8n with Cloud IAP? (maybe not needed)
- [ ] Add workflow node to n8n

## Resources

- https://docs.n8n.io/hosting/installation/docker/
- https://docs.n8n.io/hosting/installation/server-setups/google-cloud/
- https://github.com/n8n-io/n8n-hosting/tree/main

## Issues:

```
There was a problem loading init data:
Credentials could not be decrypted. The likely reason is that a different "encryptionKey" was used to encrypt the data.
```