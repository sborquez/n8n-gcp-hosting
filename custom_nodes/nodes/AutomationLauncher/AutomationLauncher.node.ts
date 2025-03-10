import {
	IExecuteFunctions,
	IDataObject,
	INodeExecutionData,
	INodeType,
	INodeTypeDescription,
	INodePropertyOptions,
	ILoadOptionsFunctions,
	IRequestOptions,
	NodeConnectionType,
	ResourceMapperField,
	ResourceMapperFields,
} from 'n8n-workflow';


export async function getPayloadFields(this: ILoadOptionsFunctions): Promise<ResourceMapperFields> {
	return {
		fields: [
			{
				id: 'firstName',
				displayName: 'First Name',
				defaultMatch: true,
				canBeUsedToMatch: true,
				required: true,
				display: true,
				type: 'string',
				// options?: INodePropertyOptions[],
			}
		]
	}
	// const automationServerUrl = this.getCurrentNodeParameter('automationServerUrl') as string;
	// const automationId = this.getCurrentNodeParameter('automationId') as string;
	// const returnData: INodePropertyOptions[] = [];
	// // const response = await this.helpers.request.call(this, 'GET', `${automationServerUrl}/automations/${automationId}/schema`);
	// const response = {
	// 	data: {
	// 		"automation1": {
	// 			"fields": [
	// 				{"displayName": "First Name", "name": "firstName", "type": "string", "default": "", "required": true},
	// 				{"displayName": "Last Name", "name": "lastName", "type": "string", "default": "", "required": true},
	// 			],
	// 		},
	// 		"automation2": {
	// 			"fields": [
	// 				{"displayName": "Email", "name": "email", "type": "string", "default": "", "required": true},
	// 			],
	// 		},
	// 	}[automationId]
	// }

	// const responseData = response.data as IDataObject;
	// for (const data of responseData.fields as IDataObject[]) {
	// 	returnData.push({
	// 		name: data.name as string,
	// 		value: data.id as string,
	// 	});
	// }
	// return returnData;
}

export class AutomationLauncher implements INodeType {
	description: INodeTypeDescription = {
		// Basic node details will go here
		displayName: 'AutomationLauncher',
		name: 'automationLauncher',
		icon: 'fa:cogs',
		group: ['transform'],
		version: 1,
		description: 'Start an Automation workflow',
		defaults: {
			name: 'AutomationLauncher',
		},
		inputs: ['main'] as NodeConnectionType[],
		outputs: ['main'] as NodeConnectionType[],
		credentials: [
			// {
			// 	name: 'automationLauncherApi',
			// 	required: true,
			// },
		],
		properties: [
			{
				displayName: 'Automation Server URL',
				name: 'automationServerUrl',
				type: 'string',
				required: true,
				default: null,
				description: 'URL of the Automation server',
			},
			{
				displayName: 'Automation ID',
				name: 'automationId',
				type: 'options',
				typeOptions: {
					loadOptionsMethod: 'getAutomations',
					loadOptionsDependsOn: [
						'automationServerUrl',
					],
				},
				default: '',
				required: true,
				description: 'Select the automation to start',
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
			// Load available automations
			async getAutomations(this: ILoadOptionsFunctions): Promise<INodePropertyOptions[]> {
				const automationServerUrl = this.getCurrentNodeParameter('automationServerUrl') as string;
				const returnData: INodePropertyOptions[] = [];
				// const response = await this.helpers.request.call(this, 'GET', `${automationServerUrl}/automations`);
				// <debug>
				const response = {
					data: {
						"server": [
							{"id": "automation1", "name": "Automation 1"},
							{"id": "automation2", "name": "Automation 2"},
						]
					}[automationServerUrl]
				}
				console.log(response);
				if (!response.data) {
					return [];
				}
				// </debug>
				const responseData = response.data as IDataObject[];
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
				const automationServerUrl = this.getCurrentNodeParameter('automationServerUrl') as string;
				const automationId = this.getCurrentNodeParameter('automationId') as string;
				return {
					fields: [
						{
							id: 'firstName',
							displayName: 'First Name',
							defaultMatch: true,
							canBeUsedToMatch: true,
							required: true,
							display: true,
							type: 'string',
						},
						{
							id: 'lastName',
							displayName: 'Last Name',
							defaultMatch: true,
							canBeUsedToMatch: true,
							required: true,
							display: true,
							type: 'string',
						},
						{
							id: automationId,
							displayName: automationId,
							defaultMatch: true,
							canBeUsedToMatch: true,
							required: true,
							display: true,
							type: 'string',
						},
					]
				}
			}
		}
	};

	// The execute method will go here
	async execute(this: IExecuteFunctions): Promise<INodeExecutionData[][]> {
		// Handle data coming from previous nodes
		const items = this.getInputData();
		let responseData;
		const returnData = [];

		// For each item, make an API call to create a contact
		for (let i = 0; i < items.length; i++) {

			const automationId = this.getNodeParameter('automationId', i) as string;
			const payloadFieldsMapper = this.getNodeParameter('payloadFields', i)
			const payloadFields = payloadFieldsMapper["value"] as IDataObject;
			const data: IDataObject = {
				automationId,
				payloadFields,
			};
			// Object.assign(data, payloadFields);
			// Make HTTP request according to https://sendgrid.com/docs/api-reference/
			const options: IRequestOptions = {
				headers: {
					'Accept': 'application/json',
				},
				method: 'PUT',
				body: {
					contacts: [
						data,
					],
				},
				url: `https://api.sendgrid.com/v3/marketing/contacts`,
				json: true,
			};
			// responseData = await this.helpers.requestWithAuthentication.call(this, 'automationLauncherApi', options);
			responseData = {
				"status": "success",
				"message": "Automation started",
			}
			Object.assign(responseData, data);
			returnData.push(responseData);
		}
		// Map data to n8n data structure
		return [this.helpers.returnJsonArray(returnData)];
	}
}

