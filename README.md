# Lab 04 — AWS Lambdas con IaC (Terraform)

**Curso:** Infraestructura como Código  
**Profesor:** Walter Ivan Leturia Rodriguez  
**Alumno:** Diego Villajulca Quispe

---

## Descripción

Infraestructura serverless para procesamiento de imágenes desplegada en AWS con Terraform. El sistema expone un endpoint HTTP para cargar imágenes, las encola en SQS y las procesa de forma asíncrona. Incluye tres entornos aislados: **DEV**, **QA** y **PROD**.

---

## Arquitectura (Diagrama de alto nivel)

```
Usuario → API Gateway (POST /upload)
              ↓
        Lambda Upload   →   S3 Bucket (uploads/)
              ↓
           SQS Queue
              ↓
        Lambda Crop     →   S3 Bucket (processed/)
```

**Recursos AWS aprovisionados:**

| Recurso | Descripción |
|---|---|
| VPC | Red privada por entorno (CIDRs distintos) |
| Subnets | 2 públicas + 2 privadas (AZ-a y AZ-b) |
| NAT Gateways | Salida a internet desde subnets privadas |
| S3 | Almacenamiento de imágenes con cifrado AES-256 |
| SQS | Cola de mensajes con Dead Letter Queue (DLQ) |
| Lambda Upload | Recibe la imagen vía API y la registra |
| Lambda Crop | Consume la cola SQS y procesa la imagen |
| API Gateway v2 | HTTP API con ruta `POST /upload` |
| VPC Endpoints | Acceso privado a S3 y SQS sin salir a internet |
| IAM Roles | Permisos mínimos por función Lambda |

---

## Entornos

Los entornos se manejan con **Terraform Workspaces**. Cada uno tiene su propia red y recursos aislados.

| Entorno | Workspace | VPC CIDR |
|---|---|---|
| Desarrollo | `dev` | `10.1.0.0/16` |
| QA | `qa` | `10.2.0.0/16` |
| Producción | `prod` | `10.0.0.0/16` |

La memoria de la Lambda de procesamiento también varía por entorno:

| Entorno | Memoria (crop-lambda) |
|---|---|
| dev | 128 MB |
| qa | 256 MB |
| prod | 512 MB |

---

## Prerrequisitos

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) configurado con perfil `admin`
- Node.js (para generar los `.zip` de las lambdas)

---

## Pasos para ejecutar

### 1. Clonar el repositorio

```bash
git clone https://github.com/villitaqt/lab04_iac-awslambda.git
cd Lab04-Iac-awslambda
```

### 2. Empaquetar las funciones Lambda

```bash
cd src/upload-lambda && zip -r ../../upload.zip . && cd ../..
cd src/crop-lambda   && zip -r ../../crop.zip .   && cd ../..
```

### 3. Inicializar Terraform

```bash
terraform init
```

### 4. Seleccionar el entorno (workspace)

```bash
# Para DEV
terraform workspace new dev     # solo la primera vez
terraform workspace select dev

# Para QA
terraform workspace new qa
terraform workspace select qa

# Para PROD
terraform workspace new prod
terraform workspace select prod
```

### 5. Revisar el plan

```bash
terraform plan
```

### 6. Aplicar la infraestructura

```bash
terraform apply
```

Al finalizar, Terraform imprime la URL del API Gateway. Ejemplo:

```
https://<id>.execute-api.us-east-1.amazonaws.com/upload
```

### 7. Probar el endpoint

```bash
curl -X POST https://<api-url>/upload \
  -H "Content-Type: application/json" \
  -d '{"filename": "foto.jpg"}'
```

### 8. Destruir la infraestructura

```bash
terraform destroy
```

> Repetir los pasos 4-8 por cada entorno (dev / qa / prod).

---

## Estructura del proyecto

```
Lab04-Iac-awslambda/
├── src/
│   ├── upload-lambda/index.js   # Lambda que recibe imágenes
│   └── crop-lambda/index.js     # Lambda que procesa desde SQS
├── main.tf                      # Recursos AWS principales
├── providers.tf                 # Proveedor AWS y tags globales
├── variables.tf                 # Declaración de variables
└── terraform.tfvars             # Valores: región y CIDRs por entorno
```
