// +--------------------------------------------------------------------
// +
// +
// +
// +    Programa  : f_freadl.prg funcoes de arquivos
// +
// +
// +
// +     Sistema:
// +
// +     Linguagem: Harbour
// +
// +     Autor: jcassiano
// +
// +     Copyright (c) 2024,  jcassiano
// +
// +
// +    Function FREADLINE(handle, line_len,lremchrexp) le uma linha
// +    FUNCTION FDELIM (cARQ, line_len) verifica se o delimitador e chr(13)chr(10) dos ou chr(10) linux
// +    SplitCommaAspas(cLINHA) "33600823";"0001";"07";"1";"SALGADOS DA ERIDIANA";"08" todos os campos estao delimitados por ";"
// +
// +
// +    Documentado em 28-Dez-2024 as 10:41 am
// +
// +
// +
// +--------------------------------------------------------------------
// +


#include "Directry.ch"

/*

    nao user nFILE apresentou erro usando outro nome como nFILEUSO

    nLASTREC:=FLINECOUNT(cARQIMP)
    zei_fort( nLASTREC,,,0)

    cDELIM:=FDELIM (cARQIMP,1024) //acha o delimitador chr(13)+chr(10) dos ou chr(10) linux usado abaixo no freadline
    nFILEuso:=FOPEN(cARQIMP) //abre o arquivo
     WHILE .T.
        cLINHA:=FREADLINE (nFILEuso, 1024 ,.T. ,cDELIM) //FREADLINE (handle, line_len,lremchrexp,cDELI)

        //operacoes da rotina

        IF cLINHA='__FINAL__' //freadline retorna __FINAL__   quando nao e mais linhas
           EXIT
        ENDIF

        zei_fort(nLASTREC,,,1)

     enddo
     fclose(nFILEuso)   //fecha o arquivo
*/


// +--------------------------------------------------------------------
// +
// +
// +
// +    Function FREADLINE(handle, line_len,lremchrexp,cDELI))
// +    arrega uma linha de um arq. texto (a partir da pos.atual do ponteiro)
// +
// +
// +--------------------------------------------------------------------
// +
// +
// +
FUNCTION FREADLINE( handle, line_len, lremchrexp, cDELI )

   LOCAL buffer, line_end, num_bytes,cRETU

// Se o tamanho da linha nao for informado, usa o predefinido MAXLINE
   IF ValType( line_len ) <> 'N'
      line_len := 1024
   ENDIF
   IF ValType( lremchrexp ) <> "L"
      lREMCHREXP := .T.
   ENDIF
   IF ValType( cDELI ) <> "C"
      cDELI := Chr( 13 ) + Chr( 10 )
   ENDIF
   cRETU:=""
// Define um buffer temporario p/ guardar o tamanho de linha  especificado
   buffer := Space( line_len )
// Carrega o texto da posicao atual ate' o tamanho de linha especificado
   num_bytes := FRead( handle, @buffer, line_len )
// Localiza a combinacao de retorno de carro/avanco de linha.
   line_end := At( cDELI, buffer )
   IF line_end = 0
      // Nao ha' retorno carro/avanco linha. Ponteiro esta' no final do
      // arq. ou linha e' grande demais. Volta ponteiro p/ inicio do arq.
      FSeek( handle, 0 )
      RETURN ( '__FINAL__' )
   ELSE
      // Move o ponteiro para o inicio da proxima linha.
      IF cDELI = Chr( 10 )   // *-1 negativo pois o buffer passa do ponto e precisa retornar ao final real da linha
         FSeek( handle, ( num_bytes * -1 ) + line_end, 1 )  // chr(10) e so um caractere nao  precisa somar +1
      ELSE
         FSeek( handle, ( num_bytes * -1 ) + line_end + 1, 1 )  // como chr(13)+chr(10) sao dois caracteres precisa somar +1
      ENDIF
      // E retorna a linha atual.
      IF lREMCHREXP //nao usar fixstrextend as funcoes que leem a informacao ira tratar
         cRETU := SubStr( buffer, 1, line_end - 1 )
         cRETU := RANGEREPL( Chr( 0 ), Chr( 9 ), cRETU, " " )   // CHR(13)+CHR(10)
         cRETU := RANGEREPL( Chr( 11 ), Chr( 12 ), cRETU, " " )   // Line Feed Manter
         cRETU := RANGEREPL( Chr( 14 ), Chr( 31 ), cRETU, " " )   // 32 space
         cRETU := RANGEREPL( Chr( 127 ), Chr( 255 ), cRETU, " " )
         RETURN cRETU
      ELSE
         RETURN ( SubStr( buffer, 1, line_end - 1 ) )
      ENDIF
   ENDIF
   RETURN cRETU


// +--------------------------------------------------------------------
// +
// +
// +
// +    Function FDELIM(ARQ, line_len , cPADRAO))
// +    verifica se o delimitador e chr(13)chr(10) dos ou chr(10) linux
// +
// +
// +--------------------------------------------------------------------
// +
// +
// +

FUNCTION FDELIM( cARQ, line_len, cPADRAO )

   LOCAL buffer, line_end, num_bytes, nhandle, cRETU

   IF ValType( line_len ) <> 'N'
      line_len := 1024
   ENDIF
   cRETU     := ""
   buffer    := Space( line_len )
   nHANDLE   := FOpen( cARQ )
   num_bytes := FRead( nhandle, @buffer, line_len )
   IF Empty( AllTrim( BUFFER ) )   // tenta com freadstr se o buffer vier vazio
      buffer := FReadStr( nhandle, line_len )
   ENDIF
   FClose( NHANDLE )

// Dos
   line_end := At( Chr( 13 ) + Chr( 10 ), buffer )  // 0D0A
   IF line_end > 0
      cRETU := Chr( 13 ) + Chr( 10 )
      RETURN cRETU
   ENDIF

// Linux
   line_end := At( Chr( 10 ), buffer )  // 0A
   IF line_end > 0
      cRETU := Chr( 10 )
      RETURN cRETU
   ENDIF

// So 13 0D
   line_end := At( Chr( 13 ), buffer )  // 0D
   IF line_end > 0
      cRETU := Chr( 13 )
      RETURN cRETU
   ENDIF


// unicode
   line_end := At( Chr( 255 ) + Chr( 254 ), buffer )
   IF line_end > 0
      cRETU := Chr( 255 ) + Chr( 254 )
      RETURN cRETU
   ENDIF

// utf-8
   line_end := At( Chr( 239 ) + Chr( 187 ) + Chr( 191 ), buffer )
   IF line_end > 0
      cRETU := Chr( 239 ) + Chr( 187 ) + Chr( 191 )
      RETURN cRETU
   ENDIF

// atribui o padrao
   IF Empty( cRETU ) .AND. ValType( cPADRAO ) = "C"
      cRETU := cPADRAO
   ENDIF

   RETURN cRETU




// +--------------------------------------------------------------------
// +
// +
// +
// +    Function SplitCommaAspas(cLINHA)
// +    todos os campos devem estar com aspas
// +
// +
// +--------------------------------------------------------------------
// +
// +
// +
FUNCTION SplitCommaAspas( cLINHA, cSEPCAMPOS )

   LOCAL aRETU, cVALOR, nPOS

// CLINHA:='"33600823";"0001";"07";"1";"SALGADOS DA ERIDIANA";"08";"20190722";"01";"";"";"20190513";"5620104";"1096100,1093702";"RUA";"EMILIO VASCONCELOS";"288";"";"CENTRO";"39790000";"MG";"4011";"33";"88333829";"";"";"";"";"adelano.deptofiscal@gmail.com";"";"'
   IF ValType( cSEPCAMPOS ) <> "C"
      cSEPCAMPOS := '";"'
   ELSE
      cSEPCAMPOS := '"' + cSEPCAMPOS + '"'
   ENDIF
   aRETU := {}
   WHILE At( cSEPCAMPOS, cLINHA ) > 0   // '";"'
      nPOS := At( cSEPCAMPOS, cLINHA )  // '";"'
      IF Left( cLINHA, 1 ) = '"'  // as vezes o primeiro campo nao e "33600823"; e sim 33600823";
         cVALOR := SubStr( cLINHA, 2, nPOS - 2 )
      ELSE
         cVALOR := SubStr( cLINHA, 1, nPOS - 1 )
      ENDIF
      cLINHA := SubStr( cLINHA, nPOS + 2 )
      // ALERT(cVALOR)
      // ALERT(cLINHA)
      AAdd( aRETU, cVALOR )
   ENDDO
   IF Len( cLINHA ) > 0  // caso o ultimo campo nao tenha delimitador
      AAdd( aRETU, StrTran( cLINHA, '"', '' ) )
   ENDIF

   RETURN aRETU

// + EOF: f_freadl.prg
// +
