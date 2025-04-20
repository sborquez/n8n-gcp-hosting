import {
	IAuthenticateGeneric,
	ICredentialTestRequest,
	ICredentialType,
	INodeProperties,
} from 'n8n-workflow';

export class TaskLauncherApiKey implements ICredentialType {
	name = 'taskLauncherApiKey';
	displayName = 'TaskLauncher API';
	properties: INodeProperties[] = [
		{
			displayName: 'API Key',
			name: 'apiKey',
			type: 'string',
			default: '',
		},
	];

	authenticate: IAuthenticateGeneric = {
		type: 'generic',
		properties: {
			headers: {
				'X-User-Api-Key': '={{$credentials.apiKey}}',
			},
		},
	};

	// test: ICredentialTestRequest = {
	// 	request: {
	// 		baseURL: 'https://api.sendgrid.com/v3',
	// 		url: '/marketing/contacts',
	// 	},
	// };
}
