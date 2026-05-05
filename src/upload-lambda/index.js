const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");
const { v4: uuidv4 } = require("uuid");

const s3 = new S3Client({});

exports.handler = async (event) => {
    try {
        const bucket = process.env.S3_BUCKET;
        const fileContent = event.isBase64Encoded ? Buffer.from(event.body, 'base64') : event.body;
        const fileName = `uploads/${uuidv4()}.jpg`;

        await s3.send(new PutObjectCommand({
            Bucket: bucket,
            Key: fileName,
            Body: fileContent,
            ContentType: "image/jpeg"
        }));

        return {
            statusCode: 200,
            body: JSON.stringify({ message: "Imagen subida con éxito", key: fileName })
        };
    } catch (error) {
        return { statusCode: 500, body: JSON.stringify({ error: error.message }) };
    }
};