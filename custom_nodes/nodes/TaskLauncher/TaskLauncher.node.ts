import {
	IExecuteFunctions,
	IDataObject,
	INodeExecutionData,
	INodeType,
	INodeTypeDescription,
	INodePropertyOptions,
	ILoadOptionsFunctions,
	NodeConnectionType,
	ResourceMapperFields,
} from 'n8n-workflow';

import {
	JobStatus,
	fetchTasks,
	fetchPayloadFields,
	startJob,
	pollJobUntilComplete
} from './TaskLauncher.helpers';

const DEFAULT_WAIT_FOR_TASK_SECONDS = 10;

export class TaskLauncher implements INodeType {
	description: INodeTypeDescription = {
		// Basic node details will go here
		displayName: 'TaskLauncher',
		name: 'taskLauncher',
		icon: 'fa:cogs',
		group: ['transform'],
		version: 1,
		description: 'Start a task workflow',
		defaults: {
			name: 'TaskLauncher',
		},
		inputs: ['main'] as NodeConnectionType[],
		outputs: ['main'] as NodeConnectionType[],
		credentials: [
			{
				name: 'taskLauncherApiKey',
				required: true,
			},
		],
		properties: [
			{
				displayName: 'Task Server URL',
				name: 'taskServerUrl',
				type: 'string',
				required: true,
				default: null,
				description: 'URL of the Task server',
			},
			{
				displayName: 'Wait for Task Interval',
				name: 'waitForTask',
				type: 'number',
				default: DEFAULT_WAIT_FOR_TASK_SECONDS,
				description: `Time in seconds to wait before checking the task status again. Default is ${DEFAULT_WAIT_FOR_TASK_SECONDS} s`,
				placeholder: '10',
			},
			{
				displayName: 'Task ID',
				name: 'taskId',
				type: 'options',
				typeOptions: {
					loadOptionsMethod: 'getTasks',
					loadOptionsDependsOn: [
						'taskServerUrl',
					],
				},
				default: '',
				required: true,
				description: 'Select the task to start',
			},
			{
				displayName: 'Use Raw Json',
				name: 'useRawJson',
				type: 'boolean',
				default: false,
				description: 'If true, the payload will be form as a raw json string',
			},
			// Use resourcer Mapper for the Payload Fields
			{
				displayName: 'Payload Fields',
				name: 'payloadFields',
				type: 'resourceMapper',
				default: {
					mappingMode: 'defineBelow',
					value: null,
				},
				typeOptions: {
					loadOptionsDependsOn: [
						'taskServerUrl',
						'taskId',
						'useRawJson',
					],
					resourceMapper: {
						resourceMapperMethod: 'getPayloadFields',
						mode: 'add',
						fieldWords: {
							singular: 'Field',
							plural: 'Fields',
						},
					},
				},
			}
		],
	};

	// Load Methods
	methods = {
		loadOptions: {
			// Load available tasks
			async getTasks(this: ILoadOptionsFunctions): Promise<INodePropertyOptions[]> {
				const taskServerUrl = this.getCurrentNodeParameter('taskServerUrl') as string;
				const credentials = await this.getCredentials('taskLauncherApiKey');
				const userAPIToken = credentials?.apiKey as string;

				const responseData = await fetchTasks.call(this, taskServerUrl, userAPIToken);
				const returnData: INodePropertyOptions[] = [];
				for (const data of responseData) {
					returnData.push({
						name: data.name as string,
						value: data.id as string,
					});
				}
				return returnData;
			},
		},
		resourceMapping: {
			// Map the fields to the payload
			async getPayloadFields(this: ILoadOptionsFunctions): Promise<ResourceMapperFields> {
				const useRawJson = this.getCurrentNodeParameter('useRawJson') as boolean;
				const taskServerUrl = this.getCurrentNodeParameter('taskServerUrl') as string;
				const taskId = this.getCurrentNodeParameter('taskId') as string;
				const credentials = await this.getCredentials('taskLauncherApiKey');
				const userAPIToken = credentials?.apiKey as string;
				return fetchPayloadFields.call(this, taskServerUrl, taskId, useRawJson, userAPIToken);
			}
		}
	};

	// The execute method will go here
	async execute(this: IExecuteFunctions): Promise<INodeExecutionData[][]> {
		// Handle data coming from previous nodes
		const items = this.getInputData();
		const returnData = [];
		const sentTasks = [];
		const credentials = await this.getCredentials('taskLauncherApiKey');
		const userAPIToken = credentials?.apiKey as string;

		// For each item, make an API call to create a contact
		for (let i = 0; i < items.length; i++) {
			const taskServerUrl = this.getNodeParameter('taskServerUrl', i) as string;
			const taskId = this.getNodeParameter('taskId', i) as string;
			const rawJson = this.getNodeParameter('useRawJson', i) as boolean;
			const payloadFieldsMapper = this.getNodeParameter('payloadFields', i) as IDataObject;

			let body = {};
			if (rawJson) {
				body = payloadFieldsMapper.value;
			} else {
				for (const property of Object.entries(payloadFieldsMapper.value)) {
					const key = property[0] as string;
					const value = property[1];
					body[key] = value;
				}
			}
			let response;
			// Start new Job
			try {
				response = await startJob(this.helpers, taskServerUrl, taskId, userAPIToken, body);
			} catch (error) {
				throw new Error(`Error fetching tasks: ${error.message}`);
			}
			if (!response) {
				throw new Error('No response from server');
			}
			const jobId = response.id as string;
			const jobStatus = response.status as JobStatus;
			if (jobStatus !== JobStatus.CREATED) {
				throw new Error(`Error creating task: ${response.message}`);
			}
			sentTasks.push(
				{
					jobId,
					jobStatus,
				}
			)
		}

		// Wait for the job to finish, iterate over the sent tasks
		for (let i = 0; i < items.length; i++) {
			const taskServerUrl = this.getNodeParameter('taskServerUrl', i) as string;
			const task = sentTasks[i];
			const jobId = task.jobId;
			const wait_for_task_s = this.getNodeParameter('waitForTask', i) as number;
			const result = await pollJobUntilComplete(this.helpers, taskServerUrl, jobId, userAPIToken, wait_for_task_s);
			returnData.push(result);
		}

		// Map data to n8n data structure
		return [this.helpers.returnJsonArray(returnData)];
	}
}
