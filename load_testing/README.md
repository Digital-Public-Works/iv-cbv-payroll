# Load Testing
## Running a Load Test
Load tests must be performed from our loadtesting EC2 instance in order for accurate readings to be useful.

Follow these steps to perform a load test:

### Preparation
1. Ensure you're running k6 within EC2
2. Ensure you've pre-scaled up the ECS service and database cluster to expected load levels. Standard levels are:
    * ECS service (app-dev) = 10 containers (tasks)
    * DB cluster (app-dev) = 10 ACUs
3. Pause the "default" queue so we don't track a ton of useless Mixpanel events during the test.
    * https://demo.divt.app/jobs      (un/pw in 1Password)

### Running the test

#### Step 1: Seed test sessions with synced data
Generate test sessions with fully synced payroll accounts in the database:
```bash
# Generate 100 test sessions (creates CbvFlows with synced PayrollAccounts)
bin/rails 'load_test:seed_sessions[100]'

# Or specify a different client_agency_id
bin/rails 'load_test:seed_sessions[100,sandbox]'
```

This will output a line like:
```
export COOKIES='cookie1,cookie2,cookie3,...'
```

Copy and run that export command.

#### Step 2: Run the load test
```bash
# Test with mixed realistic traffic (recommended)
k6 run loadtest.js --env "COOKIES=$COOKIES" --env URL=https://demo.divt.app

# Or test specific scenarios:
k6 run loadtest.js --env "COOKIES=$COOKIES" --env URL=https://demo.divt.app --env SCENARIO=sync
k6 run loadtest.js --env "COOKIES=$COOKIES" --env URL=https://demo.divt.app --env SCENARIO=pdf
k6 run loadtest.js --env "COOKIES=$COOKIES" --env URL=https://demo.divt.app --env SCENARIO=summary
k6 run loadtest.js --env "COOKIES=$COOKIES" --env URL=https://demo.divt.app --env SCENARIO=employer_search
```

Available scenarios:
- `mixed` (default) - Weighted distribution: 50% sync polling, 20% payment details, 15% summary, 10% search, 5% PDF
- `sync` - Database-intensive synchronization polling
- `payment_details` - Per-account queries and aggregation
- `summary` - Full summary with all accounts
- `pdf` - CPU-intensive PDF generation
- `employer_search` - Employer search page

#### Step 3: Record the metrics

The test will output performance metrics including:
- Request duration (p95, p99, max)
- Failed requests
- SLO violations
- Throughput per scenario

### Cleanup
1. Delete test sessions from database:
    ```bash
    # In the Rails console or via rake task
    bin/rails 'load_test:cleanup_sessions[sandbox]'
    ```

2. Delete all jobs enqueued within the "default" job queue:
    ```bash
    # in top-level of repo
    bin/ecs-console

    # in the Rails console that opens:
    > SolidQueue::Queue.new("default").clear
    ```

3. Resume the "default" queue execution.
    * https://demo.divt.app/jobs      (un/pw in 1Password)


## Developing Locally with K6
The instructions below are for local development/prototyping of the load testing script (not intended to produce calibrated metrics).

### Installing k6 locally & starting container:

```
brew install k6

docker-compose up
```

### Instructions for running load tests locally:

Grafana URL: http://localhost:3001
Default username: admin
Default password: admin

In Grafana, add a data source: choose InfluxDB

URL: http://influxdb:8086


Database: k6

HTTP method: GET

Click save & test

In Grafana, add a dashboard:

use this dashboard as inspiration:
https://grafana.com/grafana/dashboards/13719-k6-load-testing-results-by-groups/

If you'd like to import this dashboard, select "import dashboard" and copy-paste the above URL.

### Grabbing appropriate user tokens

Set up a user in the environment you'd like to load test. While logged in as the user, in the browser console, grab the cookie `_iv_cbv_payroll_session`. Put the **NON** url decoded value, supply that into USER_TOKENS below.

K6_OUT=influxdb k6 run loadtest.js --env USER_TOKENS=<COMMA_SEPERATED_TOKENS> --env URL=<example: https://demo.divt.app/cbv/employer_search>


####

instructions for running load tests on an ec2 instance
Note that there might be an EC2 instance called loadtester that has the tools necessary installed onto it.

copy the files into the ec2 instance using something like
scp -i ~/.ssh/my-ec2-key.pem load_testing/* ec2-user@<internal-ec2-link>:/home/ec2-user/

# for viewing the metrics

```
sudo yum install docker
sudo service docker start
sudo usermod -a -G docker ec2-user
sudo curl -L https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
docker-compose up
```

# for running the load tests

sudo dnf install https://dl.k6.io/rpm/repo.rpm
sudo dnf install k6

# running without dumping into influxdb

k6 run loadtest.js --env COOKIE=<YOUR_COOKIE> --env URL=https://demo.divt.app
