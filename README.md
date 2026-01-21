# Vault Secret Migration Tool

A shell script to export, update, and import secrets between paths in HashiCorp Vault.

## Overview
This script can be used to export, update and import secrets from a source to a target path in Hashicorp Vault. The current implementation assumes that source and target paths are in the same Vault instance but in case they are separate, the auth token for the second vault instance needs to be used when connecting to the target.

---

## 1. Export Secrets
After populating variables, granting execute permissions, and confirming access, execute the script with the export option:

```bash
./VaultSecretTool.sh export
```

## 2. Review and Modify

Review and update (if required) the exported JSON file. In scenarios where the target environment has a higher number of secrets (due to additional services/pods being present), we can update the JSON file to include those services, IP addresses, pods etc. (as needed).

**Note:** If the JSON format is intact and expected names along with paths is followed for secrets, the script can transform and import it.

## 3. (Optional) Generate New Passwords

If you need to generate new passwords for target secrets, execute the script with the **prepare** option:

```bash
./VaultSecretTool.sh prepare

```

*Important: Review and update (if required) the newly generated JSON file before proceeding.*

## 4. Import Secrets

Once everything has been reviewed and confirmed, execute the script with the **import** option:

```bash
./VaultSecretTool.sh import

```

## 5. Verification

Log into the Vault and confirm that all secrets have been added.

---

## Configuration Flags

| Flag | Description | Default |
| --- | --- | --- |
| `OVERWRITE_EXISTING` | Script does not overwrite by default. Set to `true` if existing secrets need to be overwritten. | `false` |
| `DEBUG` | Set to `true` for getting additional logging. | `false` |

## Dependencies

* **curl**: Required for Vault API interaction.
* **jq**: Required for JSON processing.

## License

This project is licensed under the MIT License.

