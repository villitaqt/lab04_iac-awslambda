exports.handler = async (event) => {
    // Generamos un ID simple sin librerías externas para evitar errores de despliegue
    const fakeUuid = Math.random().toString(36).substring(2, 15);
    
    return {
        statusCode: 200,
        body: JSON.stringify({ 
            message: "Imagen recibida en el sistema de Diego Villajulca", 
            fileId: `img-${fakeUuid}`,
            env: "Development (UPAO)" 
        })
    };
};