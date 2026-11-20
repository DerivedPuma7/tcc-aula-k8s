### criar cluster: utilize o arquivo de configuração presente neste mesmo diretório
```bash
kind create cluster --name aula --config kind-config.yaml
```

### definir contexto do kubectl
```bash
kubectl cluster-info --context kind-aula
```

### carregar imagens para o kind
```bash
kind load docker-image httpd:2.4 httpd:2.4-alpine busybox:1.36 --name aula
```