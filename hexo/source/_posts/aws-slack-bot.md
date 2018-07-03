---
title: Slack AWS Bot
date: 2016-10-29 20:50:17
tags:
 - Slack
 - AWS
 - Bot
category:
 - DevOps
---

Usually when you're using AWS's services, you might want to know the usage of your resources, e.g. number of running instances, estimated cost and etc. Taking advatange of Slack's webhook and AWS Service API, we can create a bot that sends AWS usage report to your slack channel periodically. This article introduces how it's achieved.

![](part1.jpg)
![](part2.jpg)

### Create the Webhook in your Slack Settings

Nagivate to your slack team management page and add a webhook, you will get a URL that is used to send message to Slack. Configure the settings to hook it to the desired channel and save it. Now sending message to the channel is just to call the URL with the correct payload.

![](slack_settings.jpg)

#### Set up IAM role or user

The best and easiest way of granting this role or user is to give `readonly` access to all services. However if you want to play safe, you can choose to only grant `read` access to the following services:

- EC2
- S3
- CloudFront
- RDS
- Elasticache
- CloudWatch
- Billing


### Write your code

I use GO to implement the code. The logic is pretty simple. I used a few libraries to achieve it.

1. github.com/robfig/cron. A cron library in GO, which helps to schdule the messages.
2. github.com/aws/aws-sdk-go. AWS SDK in GO, which is used to retrieve information from your AWS account.

You can find the source code here: https://github.com/WUMUXIAN/aws-slack-bot

The following code snippets show some examples of how relevant usage are scraped.

#### Get estimated cost

To get estimated cost, you simple use GO AWS SDK to make query to CloudWatch:

```go
params := &cloudwatch.GetMetricStatisticsInput{
	Namespace:  aws.String("AWS/Billing"),
	StartTime:  aws.Time(startTime),
	EndTime:    aws.Time(endTime),
	MetricName: aws.String("EstimatedCharges"),
	Period:     aws.Int64(86400),
	Statistics: []*string{
		aws.String("Maximum"),
	},
	Dimensions: []*cloudwatch.Dimension{
		{
			Name:  aws.String("Currency"),
			Value: aws.String("USD"),
		},
	},
}

resp, err := svc.GetMetricStatistics(params)
```

#### Get EC2 usage

Use AWS describe instance API to get the instances information and get the count of it.

```go
// Get running instances
respDescribeInstances, err := svc.DescribeInstances(&ec2.DescribeInstancesInput{
	Filters: []*ec2.Filter{
		{
			Name: aws.String("instance-state-name"),
			Values: []*string{
				aws.String("running"),
			},
		},
	},
})
if err != nil {
	fmt.Println(err.Error())
} else {
	count := 0
	for i := 0; i < len(respDescribeInstances.Reservations); i++ {
		count += len(respDescribeInstances.Reservations[i].Instances)
	}
	if count > 0 {
		ec2Usage["Running Instances"] = strconv.Itoa(count)
	}
}

// Get volumes
respDescribeVolumes, err := svc.DescribeVolumes(&ec2.DescribeVolumesInput{})
if err != nil {
	fmt.Println(err.Error())
} else {
	count := len(respDescribeVolumes.Volumes)
	if count > 0 {
		ec2Usage["EBS Volumes"] = strconv.Itoa(count)
	}
}

// Get AMIs
respDescribeImages, err := svc.DescribeImages(&ec2.DescribeImagesInput{
	Owners: aws.StringSlice([]string{os.Getenv("AWS_ACCOUNT_ID")}),
})
if err != nil {
	fmt.Println(err.Error())
} else {
	count := len(respDescribeImages.Images)
	if count > 0 {
		ec2Usage["AMI Images"] = strconv.Itoa(count)
	}
}

// Get Snapshots
respDescribeSnapshots, err := svc.DescribeSnapshots(&ec2.DescribeSnapshotsInput{
	OwnerIds: aws.StringSlice([]string{os.Getenv("AWS_ACCOUNT_ID")}),
})
if err != nil {
	fmt.Println(err.Error())
} else {
	count := len(respDescribeSnapshots.Snapshots)
	if count > 0 {
		ec2Usage["Snapshots"] = strconv.Itoa(count)
	}
}

// Get EIPs
respDescribeAddresses, err := svc.DescribeAddresses(&ec2.DescribeAddressesInput{})
if err != nil {
	fmt.Println(err.Error())
} else {
	count := len(respDescribeAddresses.Addresses)
	if count > 0 {
		ec2Usage["Elastic IPs"] = strconv.Itoa(count)
	}
}

elbSVC := elb.New(sess)
respDescribeLoadBalancers, err := elbSVC.DescribeLoadBalancers(&elb.DescribeLoadBalancersInput{})
if err != nil {
	fmt.Println(err.Error())
} else {
	count := len(respDescribeLoadBalancers.LoadBalancerDescriptions)
	if count > 0 {
		ec2Usage["Load Balancers"] = strconv.Itoa(count)
	}
}
```

#### Push message to slack

In order to make it look nice, we need to use [Slack Message Attachments](https://api.slack.com/docs/message-attachments). An example payload looks like below:

```json
{
    "attachments": [
        {
            "fallback": "Required plain-text summary of the attachment.",
            "color": "#2eb886",
            "pretext": "Optional text that appears above the attachment block",
            "author_name": "Bobby Tables",
            "author_link": "http://flickr.com/bobby/",
            "author_icon": "http://flickr.com/icons/bobby.jpg",
            "title": "Slack API Documentation",
            "title_link": "https://api.slack.com/",
            "text": "Optional text that appears within the attachment",
            "fields": [
                {
                    "title": "Priority",
                    "value": "High",
                    "short": false
                }
            ],
            "image_url": "http://my-website.com/path/to/image.jpg",
            "thumb_url": "http://example.com/path/to/thumb.png",
            "footer": "Slack API",
            "footer_icon": "https://platform.slack-edge.com/img/default_application_icon.png",
            "ts": 123456789
        }
    ]
}
```

#### Schedule it using cron

Taking advantage of cron, we can schedule it very easily. The following are some examples:

```bash
0 0 1 * * MON-FRI   // Every 1am UTC on Weekdays
0/10 0 1 * * ?      // Every 10 seconds
0/10 0 */8 * * ?    // Every 8 hours
```

### Summary

It's easy to write a bot in GO to send AWS Usage report to your Slack channel, as I has shown above. You can extend the code by contributing to the repo and adding more information to report.
