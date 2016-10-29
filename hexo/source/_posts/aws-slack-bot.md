---
title: Slack AWS Bot
date: 2016-10-29 20:50:17
tags:
 - Slack
 - AWS
 - Bot
category:
 - Devops
---

Usually when you're using AWS's services, you might want to know the usage of your resources, e.g. number of running instances, estimated cost and etc. Taking advatange of Slack's webhook and AWS Service API, we can create a bot that sends AWS usage report to your slack channel periodically. This article introduces how it's achieved.

### Create the Webhook in your Slack Settings

Nagivate to your slack team management page and add a webhook, you will get a URL that is used to send message to Slack. Configure the settings to hook it to the desired channel and save it. Now sending message to the channel is just to call the URL with the correct payload.

### Write your code

I use GO to implement the code. The logic is pretty simple. I used a few libraries to achieve it.

1. github.com/robfig/cron. A cron library in GO, which helps to schdule the messages.
2. https://github.com/aws/aws-sdk-go. AWS SDK in GO, which is used to retrieve information from your AWS account.

#### Set up IAM role or user

There two methods of granting your application to read access to your AWS account. The first method is to use IAM role, which is attached to your AWS EC2 instance, if you're deploying the bot on a EC2 instance, this is the recommended method. The second methos is to use IAM user, you can create a user and get it's credentials and set up your environment properly by using *awscli* or set the credentials in your code directly. If you set it in your code, you need to be very careful because it's possible that it will get leaked. 

#### Get estimated cost

To get estimated cost, you simple use GO AWS SDK to make query to CloudWatch:

```go
sess := session.New(&aws.Config{Region: aws.String("us-east-1")})

svc := cloudwatch.New(sess)

now := time.Now().UTC()
currentYear, currentMonth, _ := now.Date()
currentLocation := now.Location()
firstDayOfMonth := time.Date(currentYear, currentMonth, 1, 0, 0, 0, 0, currentLocation)
lastDayOfMonth := firstDayOfMonth.AddDate(0, 1, -1)

fmt.Println("Start time: ", firstDayOfMonth)
fmt.Println("End time: ", lastDayOfMonth)

params := &cloudwatch.GetMetricStatisticsInput{
	Namespace:  aws.String("AWS/Billing"),
	StartTime:  aws.Time(firstDayOfMonth),
	EndTime:    aws.Time(lastDayOfMonth),
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

if err != nil {
	fmt.Println(err.Error())
	return
}

jsonBody, _ := json.Marshal(resp)

var result result
json.Unmarshal(jsonBody, &result)
sort.Sort(result.Datapoints)

estimatedCost <- result.Datapoints[0].Maximum
```

#### Get number of running instance

Use AWS describe instance API to get the instances information and get the count of it.

```
sess := session.New(&aws.Config{Region: aws.String("us-east-1")})

svc := ec2.New(sess)

resp, err := svc.DescribeInstances(&ec2.DescribeInstancesInput{
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
	return
}
count := 0
for i := 0; i < len(resp.Reservations); i++ {
	count += len(resp.Reservations[i].Instances)
}

runningInstances <- count
```

#### Push message to slack

```go
payload := strings.NewReader(`
{
   "attachments":[
      {
         "fallback":"AWS Usage Report",
         "pretext":"AWS Usage Report",
         "color":"#D00000",
         "fields":[
            {
               "title":"Running Instances",
               "value":"` + strconv.Itoa(count) + `",
               "short":false
            },
            {
               "title":"Estimated Cost Current Month",
               "value":"$` + strconv.FormatFloat(cost, 'f', 2, 64) + ` USD",
               "short":false
            },
         ]
      }
   ]
}
`)

req, _ := http.NewRequest("POST", slackWebhookURL, payload)

req.Header.Add("content-type", "application/json")
req.Header.Add("cache-control", "no-cache")

res, _ := http.DefaultClient.Do(req)

body, _ := ioutil.ReadAll(res.Body)

res.Body.Close()
```

#### Schedule it using cron

Taking advantage of cron, we can schedule it very easily. For example, if you want to send the report to your slack channel every day at 1am UTC time.

```go
cron := cron.New()
cron.AddFunc("0 0 1 * * MON-FRI", messageSlack)
```

### Conslusion

It's easy to write a bot in GO to send AWS Usage report to your Slack channel, as I has shown above. You're not limited to do this, you can query other information you want as well. The full code is at [here](https://github.com/WUMUXIAN/aws-slack-bot).