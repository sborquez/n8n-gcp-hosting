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
	FieldTypeMap,
} from 'n8n-workflow';


const DEFAULT_WAIT_FOR_TASK_SECONDS = 10;

enum JobStatus {
	CREATED = 'created',
	PENDING = 'pending',
	RUNNING = 'running',
	COMPLETED = 'completed',
	FAILED = 'failed',
}


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
			// {
			// 	name: 'taskLauncherApi',
			// 	required: true,
			// },
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
				// TODO: extract this email from the logged user
				const userEmail = 'test@user.com';
				let response;
				try {
					const endpoint = new URL('/tasks', taskServerUrl);
					response = await this.helpers.httpRequest(
						{

							headers: {
								'Accept': 'application/json',
								'Content-Type': 'application/json',
								'x-user-email': userEmail,
							},
							method: 'GET',
							url: endpoint.toString(),
							json: true,
						},
					);
				} catch (error) {
					throw new Error(`Error fetching tasks: ${error.message}`);
				}

				const returnData: INodePropertyOptions[] = [];
				if (!response) {
					return returnData;
				}

				const responseData = response as IDataObject[];
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
				if (useRawJson) {
					return {
						fields: [
							{
								id: 'rawJson',
								displayName: 'Raw Json',
								defaultMatch: true,
								canBeUsedToMatch: true,
								required: true,
								display: true,
								type: 'object',
							},
						],
					};
				}
				const taskServerUrl = this.getCurrentNodeParameter('taskServerUrl') as string;
				const taskId = this.getCurrentNodeParameter('taskId') as string;
				// TODO: extract this email from the logged user
				const userEmail = 'test@user.com';
				let response;
				try {
					const endpoint = new URL(`/tasks/${taskId}`, taskServerUrl);
					response = await this.helpers.httpRequest(
						{
							headers: {
								'Accept': 'application/json',
								'Content-Type': 'application/json',
								'x-user-email': userEmail,
							},
							method: 'GET',
							url: endpoint.toString(),
							json: true,
						},
					);
				} catch (error) {
					throw new Error(`Error fetching tasks: ${error.message}`);
				}
				const returnData: ResourceMapperFields = {fields: []};
				if (!response) {
					return returnData;
				}
				const parametersSchema = response.parameters_schema;
				for (const property of Object.entries(parametersSchema.properties)) {
					const fieldName = property[0] as string;
					const fieldValues = property[1] as { title: string; type: string; };
					if (!fieldValues) {
						continue;
					} else if (fieldValues.type === 'integer') {
						fieldValues.type = 'number';
					}
					const fieldType = fieldValues.type as keyof FieldTypeMap;
					const fieldTitle = fieldValues.title as string;
					returnData.fields.push({
						id: fieldName,
						displayName: fieldTitle,
						defaultMatch: true,
						canBeUsedToMatch: true,
						required: parametersSchema.required.includes(fieldName),
						display: true,
						type: fieldType,
					});
				}
				return returnData;
			}
		}
	};

	// The execute method will go here
	async execute(this: IExecuteFunctions): Promise<INodeExecutionData[][]> {
		// Handle data coming from previous nodes
		const items = this.getInputData();
		const returnData = [];
		const sentTasks = [];

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
			// TODO: extract this email from the logged user or use another way to identify the user
			const userEmail = 'test@user.com';
			let response;
			// Start new Job
			try {
				const endpoint = new URL(`/execute/${taskId}`, taskServerUrl);
				response = await this.helpers.httpRequest(
					{
						headers: {
							'Accept': 'application/json',
							'Content-Type': 'application/json',
							'x-user-email': userEmail,
						},
						method: 'POST',
						url: endpoint.toString(),
						json: true,
						body: body,
					},
				);
			} catch (error) {
				throw new Error(`Error fetching tasks: ${error.message}`);
			}
			if (!response) {
				throw new Error('No response from server');
			}
			// Add job to the list of sent tasks
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
			// TODO: extract this email from the logged user
			const userEmail = 'test@user.com';
			let response;
			while (true) {
				try {
					const endpoint = new URL(`/jobs/${jobId}`, taskServerUrl);
					response = await this.helpers.httpRequest(
						{
							headers: {
								'Accept': 'application/json',
								'Content-Type': 'application/json',
								'x-user-email': userEmail,
							},
							method: 'GET',
							url: endpoint.toString(),
							json: true,
						},
					);
				} catch (error) {
					throw new Error(`Error fetching tasks: ${error.message}`);
				}
				if (!response) {
					throw new Error('No response from server');
				}
				// Check if the job finished
				if (response.status === JobStatus.COMPLETED) {
					returnData.push(response.result);
					break;
				} else if (response.status === JobStatus.FAILED) {
					throw new Error(`Execution ${jobId} failed - ERROR ${response.code}: ${response.message}.`);
				}
				// Wait for WAIT_FOR_TASK_S seconds before checking again
				const wait_for_task_s = this.getNodeParameter('waitForTask', i) as number;
				await new Promise((resolve) => setTimeout(resolve, wait_for_task_s * 1000));
			}
		}

		// Map data to n8n data structure
		return [this.helpers.returnJsonArray(returnData)];
	}
}
