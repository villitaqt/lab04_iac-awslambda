exports.handler = async (event) => {
    // SQS envía los mensajes en el array 'Records'
    for (const record of event.Records) {
        console.log("Procesando mensaje de SQS:", record.messageId);
        const body = JSON.parse(record.body);
        console.log("Imagen a procesar:", body.key);
    }
    return { status: "Procesamiento completado" };
};