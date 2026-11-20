# Roteiro do laboratório de Nomad: do Job ao Service Discovery

Aula de DevOps · Introdução ao Nomad · Prática

## Visão geral

Em cerca de 40 minutos, vamos partir de um job com uma única allocation, ainda sem endereço publicado, e chegar a três allocations registradas no catálogo de serviços do Nomad. Segue a mesma dinâmica do laboratório de Kubernetes, e cada etapa pratica um conceito da aula.

| Etapa | O que fazemos | Conceito | No lab de Kubernetes | Tempo |
| --- | --- | --- | --- | --- |
| 0 | Conhecer o cluster | Servers, clients e drivers | Etapa 0 | 4 min |
| 1 | Job com 1 allocation | Job, allocation, auto-recuperação | Pod isolado | 8 min |
| 2 | Escalar para 3 allocations | count e reconciliação | Deployment e ReplicaSet | 8 min |
| 3 | Publicar portas | Portas dinâmicas | Acesso aos Pods | 8 min |
| 4 | Registrar no catálogo | Bloco service | Service | 7 min |
| Fim | Recapitulação e limpeza | Visão do todo | Encerramento | 3 min |
| Bônus A | Porta estática e evaluation | Evaluation, falha de colocação |  | 5 min |
| Bônus B | Rolling update e rollback | Deployments do Nomad |  | 7 min |

As etapas somam 38 minutos. Como o laboratório anterior precisou de folga, a sugestão é reservar cerca de 45 minutos e deixar os bônus como opcionais.

## Antes da aula (professor)

1. Docker e Nomad instalados em todas as máquinas, de preferência na mesma versão do Nomad.
2. Todos os arquivos deste roteiro na mesma pasta.
3. Imagens já baixadas, para ninguém depender de download durante a aula:

```bash
docker pull httpd:2.4
docker pull httpd:2.4-alpine
nomad version
```

4. Agente do Nomad em modo dev, em um terminal dedicado, que fica rodando durante toda a aula:

```bash
nomad agent -dev
```

Em modo dev, o mesmo processo atua como server e como client, em um único nó, e os dados são descartados quando ele é encerrado. Se aparecer erro de permissão no Docker, confirme que o usuário está no grupo docker ou rode o agente com sudo.

Todos os demais comandos são executados em um **segundo terminal**. A interface web fica em http://localhost:4646 e pode ser aberta durante toda a aula para visualizar jobs e allocations.

## Arquivos do laboratório

- `web-v1.nomad.hcl`: job com 1 allocation, sem portas (Etapa 1)
- `web-v2.nomad.hcl`: o mesmo job com 3 allocations (Etapa 2)
- `web-v3.nomad.hcl`: 3 allocations com porta dinâmica publicada (Etapa 3)
- `web-v4.nomad.hcl`: acrescenta o registro no catálogo de serviços (Etapa 4)
- `web-estatica.nomad.hcl`: porta estática com 3 allocations (Bônus A)
- `web-bonus-update.nomad.hcl`: atualização gradual com imagem nova (Bônus B)

Dica: peça para a turma abrir um segundo terminal e a interface web desde o início. Usaremos os dois para observar o cluster em tempo real.

## Etapa 0: Conhecendo o cluster (4 min)

Objetivo: ver na prática os servers e os clients da teoria.

```bash
nomad server members
nomad node status
nomad node status -self
```

O que observar:

- Há um server, marcado como líder, e um node (client) no estado ready.
- No detalhe do node, a seção de drivers mostra o docker como detectado. É assim que o client informa aos servers o que consegue executar.
- Na interface web, as seções Servers e Clients mostram as mesmas informações.

Pergunta para a turma: o mesmo processo é server e client ao mesmo tempo. Como seria em produção? Resposta: papéis separados, normalmente 3 ou 5 servers e vários clients.

## Etapa 1: Job com uma allocation (8 min)

Objetivo: criar o primeiro job e perceber duas coisas: ainda não há endereço publicado para a aplicação, e, diferente de um Pod avulso do Kubernetes, o Nomad recria a task se ela falhar.

Arquivo `web-v1.nomad.hcl`:

```hcl
job "web" {
  datacenters = ["dc1"]
  type        = "service"

  group "apache" {
    count = 1

    task "httpd" {
      driver = "docker"

      config {
        image = "httpd:2.4"
      }
    }
  }
}
```

Primeiro, veja o que o Nomad pretende fazer, sem executar nada:

```bash
nomad job plan web-v1.nomad.hcl
```

O plan mostra que será criada 1 allocation. É um ensaio: nada foi executado ainda. Agora execute o job:

```bash
nomad job run web-v1.nomad.hcl
nomad job status web
```

Na tabela Allocations, anote o ID da allocation (os primeiros caracteres bastam) e inspecione:

```bash
nomad alloc status <alloc-id>
nomad alloc logs -stderr <alloc-id>
```

O `alloc status` mostra o client onde a allocation foi parar, o estado da task e a lista de eventos (recebida, preparada, iniciada). O Apache escreve as mensagens de inicialização em stderr, por isso o `-stderr`.

Agora tente acessar a aplicação:

```bash
curl --max-time 3 http://localhost:80
```

O esperado é uma falha de conexão: o job não declarou nenhuma porta, então o Nomad não tem endereço nenhum para informar. Em `alloc status`, a seção de endereços está vazia.

Agora o teste de auto-recuperação. Descubra o container no Docker e o derrube:

```bash
docker ps
docker kill <container-id>
nomad alloc status <alloc-id>
```

O esperado é ver nos eventos da task a falha seguida de uma reinicialização, e a task voltando ao estado running depois de alguns segundos. Repita o `alloc status` se for preciso.

Por fim, pare o job:

```bash
nomad job stop web
nomad job status web
```

O esperado é o job no estado dead (stopped).

Perguntas para a turma:

- No laboratório de Kubernetes, o Pod avulso apagado não voltou. Aqui, o container derrubado voltou. Por quê? Resposta: no Nomad não existe objeto avulso, todo job é um estado desejado que o Nomad mantém.
- Por que o job não voltou depois do `job stop`? Resposta: pararmos o job é mudar o estado desejado para nada rodando. Quem derrubou o container foi uma falha, quem parou o job fomos nós.

Nota para o professor: se algum aluno descobrir o IP do container com `docker inspect`, explique que é um detalhe interno do Docker, não um endereço gerenciado pelo Nomad.

## Etapa 2: Escalar para 3 allocations (8 min)

Objetivo: ver o `count` em ação e a reconciliação mantendo o estado desejado.

Arquivo `web-v2.nomad.hcl` (só muda o `count`):

```hcl
job "web" {
  datacenters = ["dc1"]
  type        = "service"

  group "apache" {
    count = 3

    task "httpd" {
      driver = "docker"

      config {
        image = "httpd:2.4"
      }
    }
  }
}
```

Comandos:

```bash
nomad job plan web-v2.nomad.hcl
nomad job run web-v2.nomad.hcl
nomad job status web
```

O que observar: o job voltou a existir e agora tem 3 allocations, todas no mesmo client, já que o modo dev tem um único nó. Na interface web, abra o job e veja as allocations.

Teste de reconciliação. No segundo terminal, deixe rodando:

```bash
watch -n 1 nomad job status web
```

Em um terceiro terminal, pare uma das allocations (use um ID real da listagem):

```bash
nomad alloc stop <alloc-id>
```

O esperado é ver, quase de imediato, uma allocation nova, com outro ID, substituindo a parada. Interrompa o `watch` com Ctrl+C.

Teste de escala:

```bash
nomad job scale web 5
nomad job status web
```

Para voltar ao que o arquivo declara, execute o job de novo:

```bash
nomad job run web-v2.nomad.hcl
nomad job status web
```

O esperado é que o job volte para 3 allocations. O arquivo é a fonte do estado desejado.

Perguntas para a turma:

- Por que a allocation parada foi substituída? Resposta: o job declara count = 3, e o Nomad cria uma evaluation que reconcilia o estado atual com o desejado.
- O que aconteceu no `scale` e depois no `job run`? Resposta: mudamos o estado desejado na mão, e o job run restaurou o que o arquivo declara.

## Etapa 3: Publicar portas (8 min)

Objetivo: dar às allocations um endereço publicado no client e ver que cada uma recebe uma porta diferente.

Arquivo `web-v3.nomad.hcl` (acrescenta o bloco `network` e o mapeamento de porta):

```hcl
job "web" {
  datacenters = ["dc1"]
  type        = "service"

  group "apache" {
    count = 3

    network {
      port "http" {
        to = 80
      }
    }

    task "httpd" {
      driver = "docker"

      config {
        image = "httpd:2.4"
        ports = ["http"]
      }
    }
  }
}
```

O bloco `network` pede uma porta ao client, e o `to = 80` a liga à porta 80 de dentro do container. Como não definimos um número, a porta é dinâmica.

Comandos:

```bash
nomad job plan web-v3.nomad.hcl
nomad job run web-v3.nomad.hcl
nomad job status web
nomad alloc status <alloc-id>
```

O plan indica que as allocations serão substituídas: mudar a rede exige recriá-las. No `alloc status`, olhe a seção de endereços: a porta http aparece como dinâmica, com um endereço do tipo IP:porta (em modo dev costuma ser 127.0.0.1). Repita para as outras allocations e compare: cada uma tem uma porta diferente, em geral entre 20000 e 32000.

Acesse uma delas:

```bash
curl http://<endereço-da-allocation>
```

O esperado é a mensagem It works! do Apache. Peça para a turma abrir o endereço no navegador também.

Perguntas para a turma:

- Por que cada allocation tem uma porta diferente? Resposta: elas rodam no mesmo client, e duas não podem usar a mesma porta do host.
- Se uma allocation for substituída, o endereço continua o mesmo? Resposta: não, ela recebe uma nova porta. Falta um jeito de achar os endereços atuais: é o próximo passo.

## Etapa 4: Registrar no catálogo de serviços (7 min)

Objetivo: usar o service discovery nativo do Nomad para descobrir os endereços das allocations por um nome.

Arquivo `web-v4.nomad.hcl` (acrescenta o bloco `service`):

```hcl
job "web" {
  datacenters = ["dc1"]
  type        = "service"

  group "apache" {
    count = 3

    network {
      port "http" {
        to = 80
      }
    }

    service {
      name     = "web"
      port     = "http"
      provider = "nomad"
    }

    task "httpd" {
      driver = "docker"

      config {
        image = "httpd:2.4"
        ports = ["http"]
      }
    }
  }
}
```

Atenção ao `provider = "nomad"`: por padrão o provider de um service é o Consul, que não estamos usando. Sem essa linha, o registro não funciona.

Comandos:

```bash
nomad job run web-v4.nomad.hcl
nomad service list
nomad service info web
```

O `service list` mostra o serviço web, e o `service info web` lista o endereço (IP e porta) de cada uma das 3 allocations. Compare com o que você viu no `alloc status` da etapa anterior.

O catálogo acompanha as mudanças. Pare uma allocation e consulte de novo:

```bash
nomad alloc stop <alloc-id>
nomad service info web
```

O esperado é que a lista continue com 3 endereços, agora com a allocation nova no lugar da parada. Teste um dos endereços com `curl`.

Perguntas para a turma:

- O que o catálogo resolve? Resposta: os endereços mudam, mas o nome web continua o mesmo, e quem consulta o catálogo recebe sempre a lista atual.
- Qual a diferença para o Service do Kubernetes? Resposta: aqui não há um IP virtual fixo nem balanceamento embutido. Quem consulta recebe a lista de endereços e precisa escolher um (ou usar um balanceador, como Traefik ou Nginx, que leia o catálogo). Para DNS e service mesh existe o Consul, que não usamos hoje.

## Encerramento (3 min)

Recapitule o caminho percorrido:

| Etapa | Objeto ou recurso | O que aprendemos |
| --- | --- | --- |
| 1 | Job e allocation | O Nomad mantém o estado desejado, não existe objeto avulso |
| 2 | count | Reconciliação: o Nomad repõe o que falta |
| 3 | Bloco network | Portas dinâmicas: cada allocation tem a sua |
| 4 | Bloco service | Catálogo: nome em vez de endereço |

Limpeza:

```bash
nomad job stop -purge web
nomad status
```

Para encerrar o agente, volte ao terminal dele e pressione Ctrl+C. Em modo dev, todo o estado é descartado.

## Bônus A (opcional): Porta estática e evaluation (5 min)

Objetivo: ver uma evaluation que não consegue colocar todas as allocations, e entender por que portas estáticas limitam a escala.

Primeiro, remova o job anterior para partir de um estado limpo:

```bash
nomad job stop -purge web
```

Arquivo `web-estatica.nomad.hcl` (a porta passa a ser fixa):

```hcl
job "web" {
  datacenters = ["dc1"]
  type        = "service"

  group "apache" {
    count = 3

    network {
      port "http" {
        static = 8080
        to     = 80
      }
    }

    task "httpd" {
      driver = "docker"

      config {
        image = "httpd:2.4"
        ports = ["http"]
      }
    }
  }
}
```

Comandos:

```bash
nomad job run web-estatica.nomad.hcl
nomad job status -evals web
curl http://localhost:8080
```

O esperado: apenas 1 allocation é colocada, e o status mostra uma falha de colocação para as outras 2, com a evaluation correspondente bloqueada. O curl em localhost:8080 funciona e devolve It works!.

Pergunta para a turma: por que só uma allocation foi colocada? Resposta: a porta 8080 é reservada no client, e só uma allocation pode usá-la. Como o modo dev tem um único client, as outras duas não têm onde ir. É por isso que a documentação recomenda portas dinâmicas para a maioria dos serviços.

Limpeza: `nomad job stop -purge web`.

## Bônus B (opcional): Rolling update e rollback (7 min)

Objetivo: ver a atualização gradual de um job e a volta para a versão anterior.

Suba a versão base:

```bash
nomad job run web-v4.nomad.hcl
```

Arquivo `web-bonus-update.nomad.hcl` (imagem nova e bloco `update`):

```hcl
job "web" {
  datacenters = ["dc1"]
  type        = "service"

  update {
    max_parallel     = 1
    min_healthy_time = "5s"
  }

  group "apache" {
    count = 3

    network {
      port "http" {
        to = 80
      }
    }

    service {
      name     = "web"
      port     = "http"
      provider = "nomad"
    }

    task "httpd" {
      driver = "docker"

      config {
        image = "httpd:2.4-alpine"
        ports = ["http"]
      }
    }
  }
}
```

Comandos:

```bash
nomad job run web-bonus-update.nomad.hcl
nomad job status web
nomad job history web
nomad job revert web <versão-anterior>
nomad job status web
```

O que observar: o Nomad troca as allocations uma de cada vez (`max_parallel = 1`), criando um deployment que acompanha o progresso. O `job history` lista as versões do job, e o `job revert` volta para a versão anterior, informando o número dela.

Limpeza: `nomad job stop -purge web`.

## Problemas comuns

| Sintoma | Causa provável | O que fazer |
| --- | --- | --- |
| O node não mostra o driver docker | Docker parado ou sem permissão no socket | Iniciar o Docker, conferir o grupo docker do usuário ou rodar o agente com sudo |
| Erro de conexão ao rodar comandos nomad | Agente não está rodando, ou endereço diferente | Conferir o terminal do agente e a variável NOMAD\_ADDR (padrão: http://127.0.0.1:4646) |
| Allocation presa em pending | Imagem sendo baixada | Pré-baixar as imagens com docker pull, e conferir com `nomad alloc status` |
| O service não aparece em `nomad service list` | Falta `provider = "nomad"` no bloco service | Acrescentar a linha e executar o job de novo |
| curl ao endereço da allocation falha | Endereço copiado de uma allocation já substituída | Consultar de novo com `nomad service info web` ou `nomad alloc status` |
| curl em localhost:80 funciona na Etapa 1 | Outro processo da máquina usando a porta 80 | Explicar que é outro processo, e seguir para a Etapa 2 |
| Porta 8080 ocupada no Bônus A | Outro processo usando a porta | Trocar o número da porta estática no arquivo |
