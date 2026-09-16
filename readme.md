# FCSVRDD 🚀


**FCSVRDD** é um RDD (Work Area Driver / User RDD) customizado para a linguagem **Harbour**, desenvolvido para realizar a leitura, navegação e manipulação de arquivos **CSV** grandes de forma otimizada, segura e estruturada como uma tabela de banco de dados tradicional.

---

Architecture summary



- The project is a Harbour-based custom RDD (record driver) for CSV.

- The core entry point is `FCSVRDD.prg`, which registers a custom driver named `FCSVRDD` with `rddRegister("FCSVRDD", RDT_FULL)`.

- It implements the Harbour `USRRDD` interface, not a separate DB engine. That means it plugs into the normal Harbour table API (`DBUseArea()`, `DBGoTop()`, `DBSkip()`, `FieldGet()`, etc.).

- The work area stores file handle, EOF/BOF state, field metadata, current row content, and parsed struct data in `USRRDD_AREADATA(...)`.

- `FCSV_OPEN()` is the key lifecycle method: it detects the file delimiter, reads the header if configured, builds field names/types, and calls the Harbour super open flow.

- `FCSV_READNEXT()` and `FCSV_GETVALUE()` handle record iteration and field extraction, while `SplitAspasRDD()` and `ParseFieldDefinition()` are the main parsing/typing utilities.

- `f_freadl.prg` is the low-level IO layer for reading lines and detecting DOS/Unix/UTF-8 line endings.

- `fcsvclasse.prg` is a higher-level object wrapper that exposes CSV iteration in a DBF-like class style, but it reads the same concepts in a more manual, object-oriented layer.

- `teste/test_fcsv.prg` acts as the sample harness, demonstrating the driver in use and validating CSV behavior with header detection, typed fields, and quoted values.



Tech stack



- Language: Harbour

- Database integration: Harbour custom RDD / USRRDD API

- Build system: Harbour project files (`.hbp`, `.hbc`)

- File handling: native Harbour file IO (`FOpen`, `FRead`, `FSeek`, etc.)

- Parsing: handcrafted CSV logic, including quote-aware splitting and type inference

- Typical runtime pattern: open CSV through `DBUseArea()` as if it were a table



Key modules



- `FCSVRDD.prg`

- Driver registration

- Global config toggles (`FCSV_SETDELIM`, `FCSV_USARHEADER`, `FCSV_USARTIPAGEM`, etc.)

- CSV parsing, value conversion, type detection

- Standard RDD methods (`OPEN`, `GOTOP`, `READNEXT`, `GETVALUE`, `EOF`, etc.)

- `f_freadl.prg`

- buffer-based line reading

- newline detection across OS encodings

- quote-aware split helper for CSV fields

- `fcsvclasse.prg`

- object API for direct line/field access, with class-based navigation and metadata

- `harbourcsvrdd.hbp` / `.hbc`

- compile/link metadata for Harbour library packaging

- `teste/test_fcsv.prg`

- end-to-end smoke tests/examples

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