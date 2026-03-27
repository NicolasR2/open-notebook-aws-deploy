#!/bin/bash
# Setup script - run this once after cloning in Cloud9

echo "Setting up permissions..."
chmod +x deploy.sh destroy.sh status.sh scripts/*.sh userdata/*.sh

echo "✓ All scripts are now executable"
echo ""
echo "Next steps:"
echo "  1. Edit config.env with your AWS settings"
echo "  2. Run: ./deploy.sh"
echo ""
