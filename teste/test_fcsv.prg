/*
 * Script de Teste para o FCSVRDD
 */

#include "rddsys.ch"
#include "dbstruct.ch"

REQUEST FCSVRDD

PROCEDURE Main()
   LOCAL cArquivo := "teste_dados.csv"
   LOCAL nHandle, cConteudo
   LOCAL aRow, i

   CLS
   ? "=== INICIANDO TESTES DO FCSVRDD ==="
   ?

   // 1. Criação de um arquivo CSV de exemplo usando colchetes para evitar conflitos de aspas
   cConteudo := "ID;NOME;ENDERECO;VALOR" + HB_OSNEWLINE() + ;
                [1;Empresa Alpha S/A;"Rua das Flores, 123";1500.50] + HB_OSNEWLINE() + ;
                [2;Beta Comércio;"Av. Brasil, 456, Apto 2";2300,00] + HB_OSNEWLINE() + ;
                [3;Gamma LTDA;"Praça da Sé, s/n";980.15]

   nHandle := FCreate( cArquivo )
   IF nHandle == -1
      ? "Erro ao criar o arquivo de teste!"
      RETURN
   ENDIF
   FWrite( nHandle, cConteudo )
   FClose( nHandle )

   // 2. Configuração do RDD para o arquivo de teste
   FCSV_SETDELIM( ";" )
   FCSV_USARSPLIT( .T. )     // Ativa o split robusto com SplitAspasRDD
   FCSV_USARHEADER( .T. )    // Considera a primeira linha como cabeçalho

   // 3. Tentativa de abertura usando o FCSVRDD
   ? "Abrindo arquivo com FCSVRDD..."
   DBUseArea( .T., "FCSVRDD", cArquivo, "CLIENTES", .T., .F. )

   IF NetErr()
      ? "Erro ao abrir o arquivo CSV com FCSVRDD."
      RETURN
   ENDIF

   ? "Arquivo aberto com sucesso! Alias: CLIENTES"
   ? "Total de campos detectados (FCount):", FCount()
   ?

   // Exibe a estrutura dos campos gerados pelo cabeçalho
   ? "--- Estrutura de Campos Detectada ---"
   FOR i := 1 TO FCount()
      ? "Campo " + AllTrim( Str( i ) ) + ": " + FieldName( i )
   NEXT
   ?

   // 4. Testando a navegação e leitura dos dados campo a campo
   ? "--- Navegando pelos Registros (Campo a Campo) ---"
   DBGoTop()
   WHILE !EOF()
      ? "Reg:", RecNo(), ;
        "| ID:", FieldGet(1), ;
        "| Nome:", FieldGet(2), ;
        "| Endereço:", FieldGet(3), ;
        "| Valor:", FieldGet(4)
      DBSkip()
   ENDDO
   ?

   // 5. Testando as funções auxiliares FCSV_GETLINE() e FCSV_GETROW()
   ? "--- Testando Funções Auxiliares (GETLINE e GETROW) ---"
   DBGoTop()
   WHILE !EOF()
      ? "Linha Crua (FCSV_GETLINE):", FCSV_GETLINE()
      
      aRow := FCSV_GETROW()
      ? "Array da Linha (FCSV_GETROW):", HB_ValToExp( aRow )
      ? "--------------------------------------------------"
      DBSkip()
   ENDDO

   // 6. Fechamento da área
   DBCloseArea()

   // Limpeza do arquivo de teste do disco
   FErase( cArquivo )

   ?
   ? "=== TESTES CONCLUÍDOS COM SUCESSO ==="
   RETURN