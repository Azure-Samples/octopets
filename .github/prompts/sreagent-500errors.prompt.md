Description in incident
octopets-backend container app listings api is down with 500 errors
subscription ID: 12345678-abcd-9e8f-7g6h-5i4j3k2l1m0n
resource group:octopets-rg-2
 
You must follow these Custom instructions:
 
For the incidents that are related to app down with 500 errors, please do following step by step-
- Check activity logs for deployments and draw area chart correlation of 500 errors and deployment times
- Also look at exceptions in azure monitor
- You must show me chart of 500 errors before mitigation and chart of 500 errors vs deployment activity correlation (don’t skip this), check last 15 mins of metrics to validate this
- Give me updates of your actions at every step
- Based on these, limit yourself to these mitigations only and perform the action autonomously
- If this issue is caused due to a bad deployment then Revert to previous healthy deployment. After you roll back, just give it few seconds to check the roll back status by checking the request metrics
- If this issue is caused due to low cpu or memory, Scale out container app
- Create an issue in associated GitHub repo
- In the end, Give me detailed summary and report of all the things you did to mitigate the issue
- Include the revision you reverted to in the summary
