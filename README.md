# OpenNotebook AWS Deployment

One-click AWS deployment for [OpenNotebook](https://github.com/lfnovo/open-notebook) - an open-source alternative to Google's NotebookLM.

## What This Does

Deploys a complete OpenNotebook stack on AWS:

- **OpenNotebook EC2** (t3.medium): Web UI + REST API + SurrealDB database
- **Ollama EC2** (t3.large): Local embedding model (nomic-embed-text)
- **Security Groups**: Automatic network isolation and access control

Both instances are in a VPC with proper security configurations. You bring your own LLM API key (OpenAI, Anthropic, Groq, etc.) or use any OpenAI-compatible endpoint.

## Prerequisites

- **AWS Cloud9 environment** with AWS CLI pre-installed and IAM role configured
- An EC2 Key Pair created in your AWS region
- Basic knowledge of bash/terminal

> ℹ️ **Note:** These scripts are designed to run from AWS Cloud9. Credentials are automatically available through the Cloud9 IAM role—no need to configure AWS CLI credentials manually.

## Quick Start (from Cloud9)

### 1. Clone the Repository

```bash
git clone https://github.com/NicolasR2/open-notebook-aws-deploy.git
cd open-notebook-aws-deploy
```

### 2. Configure

Edit `config.env` with your AWS settings:

```bash
AWS_REGION=us-east-1                    # Your AWS region (where Cloud9 is)
KEY_PAIR_NAME=my-key-pair               # Name of your EC2 key pair (must exist)
ENCRYPTION_KEY=change-me-to-random-32-char-string  # Random secret for encryption
```

> **AWS Credentials:** Already available in Cloud9 via IAM role—no manual setup needed!

### 2. Deploy

```bash
./deploy.sh
```

The script will:
1. Validate your AWS credentials and key pair
2. Create security groups
3. Launch Ollama EC2 instance
4. Launch OpenNotebook EC2 instance
5. Configure both instances with Docker/services
6. Print access URLs

**Deployment takes ~10-15 minutes.** Most of that is waiting for instances to boot and services to initialize.

### 3. Access

Once deployment completes, you'll see:

```
OpenNotebook UI: http://<IP>:8502
OpenNotebook API: http://<IP>:5055
```

Open the URL in your browser. The first load may take a few minutes while Docker containers start.

### 4. Configure LLM Provider

1. Go to Settings → API Keys
2. Add your LLM provider:
   - **OpenAI**: Paste your `sk-...` key
   - **Anthropic**: Paste your `sk-ant-...` key
   - **Other providers**: Groq, Mistral, Google, xAI, Perplexity, DeepSeek, etc.

OpenNotebook will auto-detect your Ollama instance for embeddings.

### 5. Test

1. Create a notebook
2. Upload a PDF or document
3. Click "Generate podcast" or start a conversation

If embeddings work, Ollama is properly configured!

## Troubleshooting

### Instances won't start

Check:
- AWS credentials are valid: `aws sts get-caller-identity`
- Key pair exists: `aws ec2 describe-key-pairs --region us-east-1`
- Region is correct in `config.env`

### OpenNotebook shows error on first load

The containers are still starting. Wait 5-10 minutes and refresh your browser.

Check logs:

```bash
ssh -i <your-key.pem> ec2-user@<notebook-ip>
docker logs open_notebook
docker logs surrealdb
```

### Ollama not detected

1. Wait for both instances to fully start (~10 minutes total)
2. SSH into OpenNotebook instance
3. Check Ollama connectivity:

```bash
curl http://<ollama-private-ip>:11434/api/version
```

If it fails, check:
- Security groups allow port 11434 between instances
- Ollama service is running on its instance

### High AWS costs

This setup is designed for development. For production:
- Use smaller instance types (`t3.small` for both)
- Use spot instances (requires different setup)
- Set up auto-shutdown schedules
- Consider managed services (e.g., RDS for database)

## Operations

### Check Status

```bash
./status.sh
```

Shows:
- Instance IDs, types, states
- Public/private IPs
- Access URLs
- SSH commands

### Stop (Pause) Instances

```bash
aws ec2 stop-instances --region us-east-1 --instance-ids <instance-id>
```

Stops instances without destroying them. Charges only for storage, not compute.

### Destroy Everything

```bash
./destroy.sh
```

Terminates both EC2 instances and deletes security groups. **This is irreversible.**

## Architecture

```
┌─────────────────────────────────────────┐
│         Your Local Machine              │
│           (Cloud9 / Laptop)             │
└────────┬────────────────────────────────┘
         │
         │ ./deploy.sh
         │
    ┌────▼────────────────────────────────────────┐
    │          AWS Default VPC                    │
    │                                             │
    │  ┌──────────────────────────────────────┐  │
    │  │  EC2: OpenNotebook (t3.medium)       │  │
    │  │  - Docker: open-notebook container   │  │
    │  │  - Docker: surrealdb container       │  │
    │  │  - Port 8502: Web UI                 │  │
    │  │  - Port 5055: REST API               │  │
    │  │  50 GB gp3 storage                   │  │
    │  └──────────┬───────────────────────────┘  │
    │             │                              │
    │             │ HTTP (private IP)            │
    │             ▼                              │
    │  ┌──────────────────────────────────────┐  │
    │  │  EC2: Ollama (t3.large)              │  │
    │  │  - Ollama service                    │  │
    │  │  - nomic-embed-text model loaded     │  │
    │  │  - Port 11434: Ollama API            │  │
    │  │  30 GB gp3 storage                   │  │
    │  └──────────────────────────────────────┘  │
    │                                             │
    └─────────────────────────────────────────────┘
```

## Security Notes

⚠️ **This configuration is for development/testing only.**

Current setup:
- ✅ Security groups restrict Ollama to OpenNotebook only
- ⚠️ OpenNotebook UI (ports 8502, 5055) open to 0.0.0.0/0
- ⚠️ SSH (port 22) open to 0.0.0.0/0
- ⚠️ No HTTPS/TLS

**For production**, consider:
- Add an Elastic IP and restrict access to your IP
- Set up HTTPS with Let's Encrypt (use reverse proxy like Nginx)
- Add basic auth to OpenNotebook (support exists in config)
- Use AWS Systems Manager Session Manager instead of SSH
- Place instances in a private subnet with NAT gateway

## Advanced Configuration

### Use Different LLM Models

Edit `config.env` to change Ollama model:

```bash
OLLAMA_MODEL=mistral        # or: neural-chat, dolphin-mixtral, etc.
```

Then re-run the Ollama setup step manually.

### Add Custom Environment Variables

Edit `userdata/notebook-setup.sh.tpl` to add:

```bash
export CUSTOM_VAR=value
```

### Persistent Configuration

All data is stored in volumes:
- Ollama models: persisted in `/app` on Ollama instance
- OpenNotebook data: persisted in `/app/notebook_data` on OpenNotebook instance
- SurrealDB: persisted in `/app/surreal_data` on OpenNotebook instance

To backup, snapshot the EBS volumes or sync volumes to S3.

## Cost Estimation

AWS Pricing (us-east-1, approximate):

| Resource | Type | Cost |
|----------|------|------|
| t3.medium | $0.0416/hr | ~$30/month if running 24/7 |
| t3.large | $0.0832/hr | ~$60/month if running 24/7 |
| 50 GB gp3 | $0.10/GB/month | ~$5/month |
| 30 GB gp3 | $0.10/GB/month | ~$3/month |
| **Total** | | **~$98/month if 24/7** |

**Tips to reduce costs:**
- Stop instances when not in use (~$0.10/month storage only)
- Use smaller instance types (`t3.small`)
- Use spot instances for non-critical workloads
- Set up AWS Budgets alerts

## Support & Issues

- **OpenNotebook bugs**: [lfnovo/open-notebook](https://github.com/lfnovo/open-notebook/issues)
- **Deployment issues**: Check logs in `/app` directories on EC2 instances
- **AWS issues**: Verify credentials, region, VPC setup

## Files

```
.
├── deploy.sh                    # Main orchestrator - run this
├── destroy.sh                   # Cleanup - deletes all resources
├── status.sh                    # Show current deployment status
├── config.env                   # Your configuration (edit before deploy)
├── scripts/
│   ├── lib.sh                   # Shared functions
│   ├── 01-security-groups.sh    # Create security groups
│   ├── 02-deploy-ollama.sh      # Launch Ollama EC2
│   └── 03-deploy-notebook.sh    # Launch OpenNotebook EC2
├── userdata/
│   ├── ollama-setup.sh          # Ollama EC2 startup script
│   └── notebook-setup.sh.tpl    # OpenNotebook EC2 startup script (template)
└── README.md                    # This file
```

## License

These deployment scripts are provided as-is. OpenNotebook is MIT licensed.

## Changelog

### v1.0 (Initial Release)
- Basic two-EC2 setup (Ollama + OpenNotebook)
- Modular script architecture
- Automatic security group configuration
- Automatic state management

---

**Happy deploying!** 🚀
