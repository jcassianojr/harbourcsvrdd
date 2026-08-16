# FCSVRDD 🚀


**FCSVRDD** é um RDD (Work Area Driver / User RDD) customizado para a linguagem **Harbour**, desenvolvido para realizar a leitura, navegação e manipulação de arquivos **CSV** grandes de forma otimizada, segura e estruturada como uma tabela de banco de dados tradicional.

---

## ⚙️ Principais Características

* **Compatibilidade com USRRDD:** Totalmente integrado à arquitetura de RDDs de usuário do Harbour.
* **Segurança com Aspas:** Suporte a campos delimitados por aspas (`SplitAspasRDD`), tratando corretamente vírgulas, pontos e vírgulas internos, aspas duplicadas e quebras dentro de valores.
* **Cabeçalho Dinâmico:** Capacidade de ler a primeira linha do arquivo para utilizá-la automaticamente como o nome real dos campos (`FCSV_USARHEADER`).
* **Delimitação Flexível:** Detecção automática do delimitador de linhas (`FDELIM`) e customização do separador de colunas (`FCSV_SETDELIM`).
* **Navegação Padrão DBF:** Compatível com comandos nativos como `DBUseArea()`, `DBGoTop()`, `DBSkip()`, `EOF()`, `FieldGet()`, entre outros.

---

## 📂 Estrutura do Projeto

* `FCSVRDD.prg` — Código principal do RDD customizado.
* `f_freadl.prg` — Funções otimizadas de leitura bufferizada de linhas e detecção de delimitadores.
* `test_fcsv.prg` — Script de exemplo e testes unitários.

---

## 🛠️ Como Utilizar

### 1. Registro e Abertura do Arquivo
Para utilizar o RDD, basta registrar o driver e abrir o seu arquivo CSV utilizando a função padrão `DBUseArea`:

```harbour
#include "rddsys.ch"

REQUEST FCSVRDD

PROCEDURE Main()
   // Configurações opcionais globais antes de abrir
   FCSV_SETDELIM( ";" )        // Define o separador de colunas
   FCSV_USARSPLIT( .T. )       // Ativa o split robusto para aspas
   FCSV_USARHEADER( .T. )      // Usa a 1ª linha como nome dos campos

   // Abre o arquivo CSV como se fosse uma tabela convencional
   DBUseArea( .T., "FCSVRDD", "dados.csv", "CLIENTES", .T., .F. )

   IF NetErr()
      ? "Erro ao abrir o arquivo CSV!"
      RETURN
   ENDIF

   // Navegando pelos registros
   DBGoTop()
   WHILE !EOF()
      ? "ID:", FieldGet(1), "| Nome:", FieldGet(2)
      DBSkip()
   ENDDO

   DBCloseArea()
RETURN