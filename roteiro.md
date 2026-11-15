# Roteiro do laboratório: do Pod ao Service

DevOps · Introdução ao Kubernetes · Parte 3 (prática)

## Visão geral

Em cerca de 40 minutos, vamos partir de um único Pod, ainda sem acesso pela rede, e chegar até a página do Apache no navegador por meio de um Service. Cada etapa pratica um conceito visto na Parte 2.

| Etapa | O que fazemos | Conceito | Tempo |
| --- | --- | --- | --- |
| 0 | Conhecer o cluster | Control plane e data plane | 4 min |
| 1 | Criar um Pod isolado | Pod, IP interno, efêmero | 7 min |
| 2 | Criar um Deployment | Deployment, ReplicaSet, auto-recuperação | 10 min |
| 3 | Criar um Service | Service, labels e selectors | 8 min |
| 4 | Acessar pelo navegador | Service NodePort | 6 min |
| Fim | Recapitulação e limpeza | Visão do todo | 3 min |

## Antes da aula (professor)

1. Docker, kind e kubectl instalados: ver docker.md e kubernetes.md na pasta `pre-requisitos`
2. Cluster criado e contexto definido: ver cluster.md na pasta `pre-requisitos`

O `kind-config.yaml` cria 1 nó de control plane e 2 workers. Se as máquinas forem modestas, remova um worker. O mapeamento da porta 30080 nesse arquivo é o que permite abrir o Service no navegador na Etapa 4.

## Arquivos do laboratório

- `kind-config.yaml`: configuração do cluster
- `pod.yaml`: o Pod isolado (Etapa 1)
- `deployment.yaml`: Deployment com 3 réplicas (Etapa 2)
- `service-clusterip.yaml`: Service interno (Etapa 3)
- `service-nodeport.yaml`: Service acessível de fora (Etapa 4)

## Etapa 0: Conhecendo o cluster (4 min)

Objetivo: ver na prática o control plane e os nós trabalhadores da teoria.

```bash
kubectl cluster-info
kubectl get nodes
kubectl get pods -n kube-system
```

O que observar:

- Os nós aparecem com os papéis control-plane e worker.
- Em `kube-system` estão os componentes que vimos: API Server, etcd, Scheduler e Controller Manager rodando como Pods no nó de control plane, além de um kube-proxy em cada nó.

Pergunta para a turma: qual desses componentes recebe os comandos que digitamos no kubectl? Resposta: o API Server.

## Etapa 1: Um Pod isolado (7 min)

Objetivo: criar a menor unidade do Kubernetes e perceber duas coisas: ele tem um IP interno, mas não é acessível de fora, e ninguém o recria se ele for apagado.

Arquivo `pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: apache
  labels:
    app: apache-pod
spec:
  containers:
    - name: apache
      image: httpd:2.4
      ports:
        - containerPort: 80
```

Comandos:

```bash
kubectl apply -f pod.yaml
kubectl get pods
kubectl get pods -o wide
kubectl describe pod apache
kubectl logs apache
```

O `-o wide` mostra o IP do Pod e em qual nó ele foi parar (trabalho do Scheduler). No `describe`, vá até o final e leia a lista de eventos: ela conta a história do Pod (agendado, imagem, container criado, iniciado).

Agora tente acessá-lo pela rede:

```bash
POD_IP=$(kubectl get pod apache -o jsonpath='{.status.podIP}')
echo $POD_IP
curl --max-time 3 http://$POD_IP
```

O esperado é que o curl falhe por tempo esgotado: o IP do Pod é interno ao cluster. Para provar que o Pod está funcionando, vamos acessá-lo de dentro do cluster, com um Pod temporário:

```bash
kubectl run teste --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- http://$POD_IP
```

O esperado é a mensagem It works! do Apache. Agora apague o Pod:

```bash
kubectl delete pod apache
kubectl get pods
```

O esperado é a mensagem No resources found: o Pod não voltou.

Pergunta para a turma: quem deveria recriar esse Pod? Resposta: um ReplicaSet, que ainda não existe. Isso nos leva ao Deployment.

## Etapa 2: Deployment, ReplicaSet e Pods (10 min)

Objetivo: ver a hierarquia Deployment, ReplicaSet e Pods e a auto-recuperação funcionando.

Arquivo `deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: apache
          image: httpd:2.4
          ports:
            - containerPort: 80
```

Comandos:

```bash
kubectl apply -f deployment.yaml
kubectl get deployment,replicaset,pods
kubectl get pods -o wide
```

O que observar: o Deployment criou um ReplicaSet, e o ReplicaSet criou 3 Pods. Os nomes dos Pods carregam o nome do ReplicaSet, que carrega o nome do Deployment. Em `-o wide`, veja como os Pods se distribuem entre os nós.

Teste de auto-recuperação. No segundo terminal, deixe rodando:

```bash
kubectl get pods -w
```

No primeiro terminal, apague um dos Pods (use um nome real da listagem):

```bash
kubectl delete pod <nome-do-pod>
```

O esperado é ver, quase de imediato, um Pod novo nascendo para substituir o apagado. Interrompa o `-w` com Ctrl+C.

Teste de escala:

```bash
kubectl scale deployment web --replicas=5
kubectl get pods
```

Para voltar ao estado descrito no arquivo, reaplique-o:

```bash
kubectl apply -f deployment.yaml
kubectl get pods
```

O esperado é que o cluster volte para 3 Pods. O arquivo é a fonte do estado desejado.

Perguntas para a turma:

- Por que o Pod apagado voltou, e o Pod da Etapa 1 não? Resposta: agora existe um ReplicaSet vigiando o número de cópias.
- O que aconteceu com o scale e depois com o apply? Resposta: mudamos o estado desejado na mão, e o apply restaurou o que o arquivo declara.

## Etapa 3: Service dentro do cluster (8 min)

Objetivo: dar um endereço estável aos Pods e ver o Service encontrando-os por labels.

Arquivo `service-clusterip.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  type: ClusterIP
  selector:
    app: web
  ports:
    - port: 80
      targetPort: 80
```

Comandos:

```bash
kubectl apply -f service-clusterip.yaml
kubectl get service web
kubectl describe service web
```

No `describe`, olhe a linha Endpoints: ela lista os IPs dos 3 Pods. O Service os encontrou porque o selector `app: web` combina com os labels dos Pods. Compare esses IPs com os de `kubectl get pods -o wide`.

Agora acesse o Service pelo nome, a partir de um Pod temporário:

```bash
kubectl run teste --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- http://web
```

O esperado é a mensagem It works! Note que usamos o nome do Service, e não o IP de um Pod.

O Service acompanha as mudanças. Apague um Pod e veja os Endpoints se atualizarem:

```bash
kubectl delete pod <nome-do-pod>
kubectl describe service web
```

Perguntas para a turma:

- Os IPs dos Pods mudam quando um Pod é recriado. Por que o acesso pelo nome `web` continua funcionando? Resposta: o Service tem IP e nome fixos e atualiza a lista de destinos sozinho.
- Como o Service sabe quais Pods são dele? Resposta: pelo selector, que casa com os labels.

## Etapa 4: Service para fora do cluster (6 min)

Objetivo: acessar a aplicação pelo navegador. O tipo ClusterIP só é visível dentro do cluster; para chegar de fora, usamos NodePort.

Arquivo `service-nodeport.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  type: NodePort
  selector:
    app: web
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30080
```

Comandos:

```bash
kubectl apply -f service-nodeport.yaml
kubectl get service web
curl http://localhost:30080
```

O esperado: na coluna PORT(S) aparece `80:30080/TCP`, e o curl devolve It works!. Peça para a turma abrir http://localhost:30080 no navegador.

Observe que usamos o mesmo nome `web`: o apply atualizou o Service existente, trocando o tipo. Esse é o modelo declarativo de novo.

Se o cluster tiver sido criado sem o mapeamento de porta, use um túnel temporário:

```bash
kubectl port-forward service/web 8080:80
```

E acesse http://localhost:8080 (interrompa com Ctrl+C).

## Encerramento (3 min)

Recapitule o caminho percorrido:

| Etapa | Objeto | O que aprendemos |
| --- | --- | --- |
| 1 | Pod | Roda a aplicação, mas é descartável e não é acessível de fora |
| 2 | Deployment e ReplicaSet | Mantêm o número de cópias e recriam o que falha |
| 3 | Service ClusterIP | Endereço estável, encontra Pods por labels |
| 4 | Service NodePort | Porta aberta nos nós para acesso externo |

Limpeza:

```bash
kubectl delete -f service-nodeport.yaml
kubectl delete -f deployment.yaml
kubectl get all
```

Para apagar o cluster inteiro (opcional, ao final da aula):

```bash
kind delete cluster --name aula
```

## Bônus (opcional): Rolling update e rollback (5 min)

Use se sobrar tempo, antes da limpeza. Mantenha em outro terminal um `curl http://localhost:30080` repetido para mostrar que o serviço não cai durante a troca.

```bash
kubectl set image deployment/web apache=httpd:2.4-alpine
kubectl rollout status deployment/web
kubectl get replicaset
kubectl rollout history deployment/web
kubectl rollout undo deployment/web
kubectl get pods
```

O que observar: ao trocar a imagem, aparece um ReplicaSet novo, os Pods são trocados aos poucos, e o ReplicaSet antigo fica guardado com 0 Pods. O `undo` volta para ele.

Observação: o `set image` é uma mudança imperativa, e o `deployment.yaml` continua dizendo httpd:2.4. Em um projeto real, a imagem nova seria editada no arquivo e reaplicada.

## Problemas comuns

| Sintoma | Causa provável | O que fazer |
| --- | --- | --- |
| ImagePullBackOff ou ErrImagePull | Imagem não carregada no cluster e sem acesso à internet | Rodar o `kind load docker-image` da seção de preparação |
| Pod preso em Pending | Cluster sem recursos ou nós fora do ar | `kubectl describe pod <nome>` e ver os eventos; `kubectl get nodes` |
| localhost:30080 recusa conexão | Cluster criado sem o kind-config.yaml | Usar `kubectl port-forward service/web 8080:80` |
| curl ao IP do Pod funciona na Etapa 1 | Ambiente com rota até a rede dos Pods | Explicar que o IP é interno e pode mudar, e seguir para a Etapa 2 |
| kubectl aponta para outro cluster | Contexto errado | `kubectl config use-context kind-aula` |
| Porta 30080 já em uso na máquina | Outro processo usando a porta | Liberar a porta ou usar o port-forward |
