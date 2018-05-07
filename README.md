# VividCortex ECS Container

Run VividCortex Agent in an ECS container with access to SSM Parameter Store via Chamber.
See VividCortex's docs on a [containerized installation][1].

[1]: https://docs.vividcortex.com/getting-started/containerized-installation/

----
## AWS Systems Manager Parameter Store

* `prod-vividcortex/agent-api-token` - The VividCortex API Token.
* `prod-vividcortex/agent-hostname` - The hostname the VividCortex agent should report instead of an ECS derrived hostname.
* `prod-vividcortex/database-urls` - comma-delimited list of database urls. E.g. monitor two Aurora Clusters:

      `mysql://user:password@aurora-cluster-endpoint1.cluster-dzqxejjowvwp.us-east-1.rds.amazonaws.com:3306/,mysql://user:password@aurora-cluster-endpoint2.cluster-dzqxejjowvwp.us-east-1.rds.amazonaws.com:3306/`

----
## Building locally

The VividCortex agent requires the API token at install time.

```shell
$ docker build --force-rm --build-arg VC_API_TOKEN=${VC_API_TOKEN} -t vcimage .
```

If you have your `AWS_*` environment variables set on your local workstation you can use this command to verify access to SSM Parameter store:

```shell
$ docker run --rm -it $(for env in $(set |grep '^AWS_') ; do echo -n "-e ${env} " ; done) --entrypoint /bin/sh vcimage:latest

/ # chamber read -q prod-vividcortex agent-api-token
XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```


### AWS CodeBuild

AWS CodeBuild can be used to build and push to Elastic Container Repository (ECR).

The following BuildProject in-line buildspec.yml can be used (which is based upon [AWS ECS CD Pipeline docs][2]):

[2]: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-cd-pipeline.html

```yaml
version: 0.2

env:
  variables:
     REPO_NAME: "vividcortex"
     AWS_DEFAULT_REGION: "us-east-1"
     AWS_ACCOUNT_ID: "{AWS_ACCOUNT_ID}"
  parameter-store:
     VC_API_TOKEN: "/prod-vividcortex/agent-api-token"

phases:
  pre_build:
    commands:
      - set |egrep '^(AWS|CODEBUILD)'
      - echo Logging in to Amazon ECR...
      - aws --version
      - $(aws ecr get-login --region $AWS_DEFAULT_REGION --no-include-email)
      - REPOSITORY_URI=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$REPO_NAME
  build:
    commands:
      - echo Build started on `date`
      - echo Building the Docker image...
      - docker build --build-arg VC_API_TOKEN=$VC_API_TOKEN --tag $REPOSITORY_URI:latest .
      - docker tag $REPOSITORY_URI:latest $REPOSITORY_URI:$IMAGE_TAG
  post_build:
    commands:
      - echo Build completed on `date`
      - echo Pushing the Docker images...
      - docker push $REPOSITORY_URI:latest
      - docker push $REPOSITORY_URI:$IMAGE_TAG
      - echo Writing image definitions file...
      - printf '[{"name":"vividcortex","imageUri":"%s"}]' $REPOSITORY_URI:$IMAGE_TAG > imagedefinitions.json
artifacts:
    files: imagedefinitions.json
```


----
## Example ECS task definition

```json
{
  "family": "vividcortex-agent",
  "taskRoleArn": "arn:aws:iam::{AWS_ACCOUNT_ID}:role/vividcortex-agent-ecs-task",
  "executionRoleArn": "arn:aws:iam::{AWS_ACCOUNT_ID}:role/ecsTaskExecutionRole",
  "networkMode": "bridge",
  "containerDefinitions": [
    {
      "name": "vividcortex-1",
      "image": "{AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/vividcortex:latest",
      "cpu": 1024,
      "memory": 2048,
      "essential": true,
      "environment": [
        ...
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "vividcortex-agent",
          "awslogs-region": "us-east-1"
        }
      }
    }
  ],
  "requiresCompatibilities": [
    "EC2"
  ]
}
```

Note: CPU (`1024`) & memory (`2048`) are based upon recommendations from VividCortex support: a `t2.small` will generally suffice to monitor RDS instances.

### Useful Environment Variables for ECS

If you need to use a KMS Key Alias different from the Chamber default, `parameter_store_key`, set `CHAMBER_KMS_KEY_ALIAS`. The default Chamber _service_ is `prod-vividcortex`. If you need to test at task runtime: `chamber_service=staging-vividcortex`

```json
"environment": [
  {
    "name": "CHAMBER_KMS_KEY_ALIAS",
    "value": "aws/ssm"
  },
  {
    "name": "chamber_service",
    "value": "staging-vividcortex"

  }
],
```


### Optional: CloudWatch Logs

Create the CloudWatch log-group
`aws logs create-log-group --log-group-name vividcortex-agent --region us-east-1`


### ECS Task IAM Role

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CloudWatch",
      "Effect": "Allow",
      "Action": [
        "rds:DescribeDBInstances",
        "rds:DescribeDBClusters",
        "logs:GetLogEvents",
        "cloudwatch:ListMetrics",
        "cloudwatch:GetMetricStatistics"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ReadParameterStore",
      "Effect": "Allow",
      "Action": "ssm:GetParameters",
      "Resource": [
        "arn:aws:ssm:us-east-1:{AWS_ACCOUNT_ID}:parameter/prod-vividcortex/*",
        "arn:aws:ssm:us-east-1:{AWS_ACCOUNT_ID}:parameter/staging-vividcortex/*"
      ]
    },
    {
      "Sid": "ReadKMS",
      "Effect": "Allow",
      "Action": [
        "kms:ListKeys",
        "kms:ListAliases",
        "kms:Describe*",
        "kms:Decrypt"
      ],
      "Resource": [
        "arn:aws:kms:us-east-1:{AWS_ACCOUNT_ID}:alias/parameter_store_key",
        "arn:aws:kms:us-east-1:{AWS_ACCOUNT_ID}:alias/aws/ssm"
      ]
    }
  ]
}
```
