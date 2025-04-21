import {
	IExecuteFunctions,
	INodeExecutionData,
	INodeType,
	INodeTypeDescription,
} from 'n8n-workflow';
import axios from 'axios';

export class WorkflowTrigger implements INodeType {
	description: INodeTypeDescription = {
		displayName: 'Workflow Trigger',
		name: 'workflowTrigger',
		group: ['transform'],
		version: 1,
		description: 'Triggers a workflow execution and optionally waits for completion',
		defaults: {
			name: 'Workflow Trigger',
			color: '#1A82E2',
		},
        inputs: [{ type: 'main' }],
        outputs: [{ type: 'main' }],
		properties: [
			{
				displayName: 'Trigger Endpoint',
				name: 'triggerEndpoint',
				type: 'string',
				default: '',
				placeholder: 'https://your-api.com/trigger',
				required: true,
				description: 'The endpoint to trigger the workflow.',
			},
			{
				displayName: 'Status Endpoint',
				name: 'statusEndpoint',
				type: 'string',
				default: '',
				placeholder: 'https://your-api.com/status',
				required: false,
				description: 'The endpoint to check the status of the workflow. If null, does not wait for completion.',
			},
			{
				displayName: 'Workflow Name',
				name: 'workflowName',
				type: 'string',
				default: '',
				required: true,
				description: 'The name of the workflow to execute.',
			},
			{
				displayName: 'Workflow Arguments',
				name: 'workflowArguments',
				type: 'json',
				default: '{}',
				required: true,
				description: 'Arguments to pass to the workflow.',
			},
			{
				displayName: 'Status Check Interval (seconds)',
				name: 'statusCheckInterval',
				type: 'number',
				default: 5,
				required: true,
				description: 'Interval in seconds to check the status if a status endpoint is provided.',
			},
			{
				displayName: 'Timeout (seconds)',
				name: 'timeout',
				type: 'number',
				default: null,
				required: false,
				description: 'Maximum time to wait for the workflow to complete. If null, waits indefinitely.',
			},
		],
	};

	async execute(this: IExecuteFunctions): Promise<INodeExecutionData[][]> {
		const items = this.getInputData();
		const returnData: INodeExecutionData[] = [];

		for (let i = 0; i < items.length; i++) {
			const triggerEndpoint = this.getNodeParameter('triggerEndpoint', i) as string;
			const statusEndpoint = this.getNodeParameter('statusEndpoint', i) as string;
			const workflowName = this.getNodeParameter('workflowName', i) as string;
			const workflowArguments = this.getNodeParameter('workflowArguments', i) as object;
			const statusCheckInterval = this.getNodeParameter('statusCheckInterval', i) as number;
			const timeout = this.getNodeParameter('timeout', i) as number | null;

			// Trigger the workflow
			const triggerResponse = await axios.post(triggerEndpoint, {
				workflow_name: workflowName,
				workflow_arguments: workflowArguments,
			});

			if (triggerResponse.status !== 200) {
				throw new Error(`Failed to trigger workflow: ${triggerResponse.statusText}`);
			}

			const jobId = triggerResponse.data.job_id;
			let finalResult = { job_id: jobId, status: 'unknown', output: null, error: null };

			// Check status if endpoint is provided
			if (statusEndpoint) {
				let status = 'pending';
				const startTime = Date.now();
				while (status === 'pending' || status === 'running') {
					if (timeout !== null && (Date.now() - startTime) / 1000 > timeout) {
						throw new Error(`Workflow execution timeout exceeded (${timeout} seconds).`);
					}

					await new Promise(resolve => setTimeout(resolve, statusCheckInterval * 1000));
					const statusResponse = await axios.get(`${statusEndpoint}/${jobId}`);
					if (statusResponse.status !== 200) {
						throw new Error(`Failed to check workflow status: ${statusResponse.statusText}`);
					}
					finalResult = statusResponse.data;
					status = finalResult.status;
				}
			}

			returnData.push({ json: finalResult });
		}

		return [returnData];
	}
}
