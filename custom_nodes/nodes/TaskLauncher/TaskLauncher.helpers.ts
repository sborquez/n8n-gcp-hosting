import {
	IDataObject,
	ILoadOptionsFunctions,
	ResourceMapperFields,
	FieldTypeMap,
	IExecuteFunctions,
} from 'n8n-workflow';

export const enum JobStatus {
	CREATED = 'created',
	PENDING = 'pending',
	RUNNING = 'running',
	COMPLETED = 'completed',
	FAILED = 'failed',
}

export const buildAuthHeaders = (apiKey: string) => ({
	'Accept': 'application/json',
	'Content-Type': 'application/json',
	'X-User-Api-Key': apiKey,
});

export const delay = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

export async function fetchTasks(this: ILoadOptionsFunctions, taskServerUrl: string, apiKey: string) {
	const endpoint = new URL('/tasks', taskServerUrl);
	const response = await this.helpers.httpRequest({
		method: 'GET',
		url: endpoint.toString(),
		json: true,
		headers: buildAuthHeaders(apiKey),
	});
	return response as IDataObject[];
}

export async function fetchPayloadFields(
	this: ILoadOptionsFunctions,
	taskServerUrl: string,
	taskId: string,
	useRawJson: boolean,
	apiKey: string,
): Promise<ResourceMapperFields> {
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

	const endpoint = new URL(`/tasks/${taskId}`, taskServerUrl);
	const response = await this.helpers.httpRequest({
		method: 'GET',
		url: endpoint.toString(),
		json: true,
		headers: buildAuthHeaders(apiKey),
	});

	const returnData: ResourceMapperFields = { fields: [] };
	const parametersSchema = response.parameters_schema;
	for (const [fieldName, fieldValues] of Object.entries(parametersSchema.properties)) {
		const { title, type } = fieldValues as { title: string; type: string };
		const finalType = type === 'integer' ? 'number' : type;
		returnData.fields.push({
			id: fieldName,
			displayName: title,
			defaultMatch: true,
			canBeUsedToMatch: true,
			required: parametersSchema.required.includes(fieldName),
			display: true,
			type: finalType as keyof FieldTypeMap,
		});
	}
	return returnData;
}

export async function startJob(
	helpers: IExecuteFunctions['helpers'],
	taskServerUrl: string,
	taskId: string,
	apiKey: string,
	body: IDataObject,
) {
	const endpoint = new URL(`/execute/${taskId}`, taskServerUrl);
	return helpers.httpRequest({
		method: 'POST',
		url: endpoint.toString(),
		json: true,
		headers: buildAuthHeaders(apiKey),
		body,
	});
}

export async function pollJobUntilComplete(
	helpers: IExecuteFunctions['helpers'],
	taskServerUrl: string,
	jobId: string,
	apiKey: string,
	waitSeconds: number,
): Promise<IDataObject> {
	while (true) {
		const endpoint = new URL(`/jobs/${jobId}`, taskServerUrl);
		const response = await helpers.httpRequest({
			method: 'GET',
			url: endpoint.toString(),
			json: true,
			headers: buildAuthHeaders(apiKey),
		});
		if (!response) throw new Error('No response from server');
		if (response.status === 'completed') return response.result;
		if (response.status === 'failed') {
			throw new Error(`Execution ${jobId} failed - ERROR ${response.code}: ${response.message}.`);
		}
		await delay(waitSeconds * 1000);
	}
}
