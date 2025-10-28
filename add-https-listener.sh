#!/bin/bash
CERT_ARN="arn:aws:acm:us-east-1:637423327454:certificate/fe6974ca-0fab-4f71-980c-82210cac1e91"
ALB_ARN="arn:aws:elasticloadbalancing:us-east-1:637423327454:loadbalancer/app/agent-marketing-dev-alb/78f7c1114bf87e80"
TARGET_GROUP_ARN="arn:aws:elasticloadbalancing:us-east-1:637423327454:targetgroup/agent-marketing-dev-tg-ssl/4a667d9394966b6c"

# Check certificate status
STATUS=$(aws acm describe-certificate --certificate-arn $CERT_ARN | jq -r '.Certificate.Status')

if [ "$STATUS" = "ISSUED" ]; then
    echo "Certificate is validated! Adding HTTPS listener..."
    
    # Add HTTPS listener
    aws elbv2 create-listener \
        --load-balancer-arn $ALB_ARN \
        --protocol HTTPS \
        --port 443 \
        --certificates CertificateArn=$CERT_ARN \
        --default-actions Type=forward,TargetGroupArn=$TARGET_GROUP_ARN
    
    echo "HTTPS listener added successfully!"
    echo "You can now access: https://dev.amoslabs.com"
else
    echo "Certificate is still pending validation. Status: $STATUS"
    echo "Please ensure the CNAME record is added in GoDaddy."
fi
