/*
 * FCSVRDD RDD - Completo, Otimizado e Seguro para Arquivos CSV Grandes
 * Inclui: Tipagem Dinâmica, Split Robusto, Detecção Automática (Pipe/Tab/Tipado)
 */

#include "rddsys.ch"
#include "hbusrrdd.ch"
#include "fileio.ch"
#include "error.ch"
#include "dbstruct.ch"
#include "dbinfo.ch"

ANNOUNCE FCSVRDD

STATIC s_nReadSize      := 1024
STATIC s_lUseSplit      := .F.
STATIC s_cFieldDelim    := ";"
STATIC s_lUseHeader     := .F.
STATIC s_lUseRecCount   := .F.
STATIC s_lUseTypedCSV   := .F.  // o motor rdd trabalha tipado mais em csv e melhor usar carater e so o retono tipado com o parametro s_lRetornaTipado
STATIC s_lRetornaTipado := .F. // Mod 1: Parâmetro para retornar dados já convertidos (Tipados)
STATIC s_aManualHeader  := {}  // Armazena a matriz de cabeçalho/tipagem passada manualmente

// +--------------------------------------------------------------------
// + Funções de Configuração Global
// +--------------------------------------------------------------------

FUNCTION FCSV_TAMANHOLEITURA( nSize )
   IF ValType( nSize ) == "N"
      s_nReadSize := nSize
   ENDIF
   RETURN s_nReadSize

FUNCTION FCSV_USARSPLIT( lUse )
   IF ValType( lUse ) == "L"
      s_lUseSplit := lUse
   ENDIF
   RETURN s_lUseSplit

FUNCTION FCSV_SETDELIM( cDelim )
   IF ValType( cDelim ) == "C"
      s_cFieldDelim := cDelim
   ENDIF
   RETURN s_cFieldDelim

FUNCTION FCSV_USARHEADER( lUse )
   IF ValType( lUse ) == "L"
      s_lUseHeader := lUse
   ENDIF
   RETURN s_lUseHeader

FUNCTION FCSV_USARRECCOUNT( lUse )
   IF ValType( lUse ) == "L"
      s_lUseRecCount := lUse
   ENDIF
   RETURN s_lUseRecCount

FUNCTION FCSV_USARTIPAGEM( lUse )
   IF ValType( lUse ) == "L"
      s_lUseTypedCSV := lUse
   ENDIF
   RETURN s_lUseTypedCSV

// Função para ativar/desativar a conversão dos dados no GetValue (Mod 1)
FUNCTION FCSV_RETORNATIPADO( lUse )
   IF ValType( lUse ) == "L"
      s_lRetornaTipado := lUse
   ENDIF
   RETURN s_lRetornaTipado

// Permite injetar o cabeçalho/estrutura manualmente via matriz (Array)
FUNCTION FCSV_SETCABECALHO( aCabec )
   IF ValType( aCabec ) == "A"
      s_aManualHeader := aCabec
      s_lUseHeader    := .T.
      IF Len( aCabec ) > 0 .AND. At( ",", aCabec[1] ) > 0
         s_lUseTypedCSV := .T.
      ENDIF
   ENDIF
   RETURN s_aManualHeader

// +--------------------------------------------------------------------
// + Retorna a linha inteira crua da Work Area ativa sem alterar colunas
// +--------------------------------------------------------------------
FUNCTION FCSV_GETLINE()
   LOCAL aWData, cLine := ""
   
   aWData := USRRDD_AREADATA( Select() )
   IF ValType( aWData ) == "A" .AND. Len( aWData ) >= 6
      cLine := aWData[ 6 ] 
   ENDIF
   
   RETURN cLine

// +--------------------------------------------------------------------
// + Retorna um Array com os valores dos campos da linha atual com segurança
// +--------------------------------------------------------------------
FUNCTION FCSV_GETROW()
   LOCAL aWData, cLine := "", aRow := {}
   
   aWData := USRRDD_AREADATA( Select() )
   IF ValType( aWData ) == "A" .AND. Len( aWData ) >= 6
      cLine := aWData[ 6 ]
   ENDIF
   
   IF !Empty( cLine )
      IF Empty( s_cFieldDelim )
         aRow := { cLine }
      ELSEIF s_lUseSplit
         aRow := SplitAspasRDD( cLine, s_cFieldDelim )
      ELSE
         aRow := hb_ATokens( cLine, s_cFieldDelim )
      ENDIF
   ENDIF
   
   RETURN aRow

// +--------------------------------------------------------------------
// + Retorna o Array Auxiliar com a estrutura original tipada do CSV
// +--------------------------------------------------------------------
FUNCTION FCSV_GETSTRUCTORIGINAL()
   LOCAL aWData, aStruct := {}
   
   aWData := USRRDD_AREADATA( Select() )
   IF ValType( aWData ) == "A" .AND. Len( aWData ) >= 8
      aStruct := aWData[ 8 ]
   ENDIF
   
   RETURN aStruct

// +--------------------------------------------------------------------
// + Split Robusto (Trata mistas com/sem aspas, aspas internas e casos atípicos)
// +--------------------------------------------------------------------
FUNCTION SplitAspasRDD( cLINHA, cSEPCAMPOS )
   LOCAL aRETU := {}, cVALOR := "", lInQuotes := .F., nI := 1, nLen, cChar
   LOCAL lFirstField := .T.
   
   IF ValType( cSEPCAMPOS ) <> "C" .OR. Empty( cSEPCAMPOS )
      RETURN { cLINHA }
   ENDIF
   
   nLen := Len( cLINHA )
   WHILE nI <= nLen
      cChar := SubStr( cLINHA, nI, 1 )
      
      IF cChar == '"'
         IF lFirstField .AND. Len( cVALOR ) > 0 .AND. !lInQuotes
            cVALOR += cChar
         ELSE
            IF lInQuotes .AND. nI < nLen .AND. SubStr( cLINHA, nI + 1, 1 ) == '"'
               cVALOR += '"'
               nI++
            ELSE
               lInQuotes := !lInQuotes
            ENDIF
         ENDIF
      ELSEIF cChar == cSEPCAMPOS .AND. !lInQuotes
         cVALOR := AllTrim( cVALOR )
         IF Left( cVALOR, 1 ) == '"' .AND. Right( cVALOR, 1 ) == '"' .AND. Len( cVALOR ) >= 2
            cVALOR := SubStr( cVALOR, 2, Len( cVALOR ) - 2 )
         ELSEIF Left( cVALOR, 1 ) == '"'
            cVALOR := SubStr( cVALOR, 2 )
         ENDIF
         AAdd( aRETU, cVALOR )
         cVALOR := ""
         lFirstField := .F.
      ELSE
         cVALOR += cChar
      ENDIF
      nI++
   ENDDO
   
   IF Len( cVALOR ) > 0
      cVALOR := AllTrim( cVALOR )
      IF Left( cVALOR, 1 ) == '"' .AND. Right( cVALOR, 1 ) == '"' .AND. Len( cVALOR ) >= 2
         cVALOR := SubStr( cVALOR, 2, Len( cVALOR ) - 2 )
      ELSEIF Left( cVALOR, 1 ) == '"'
         cVALOR := SubStr( cVALOR, 2 )
      ENDIF
      cVALOR := StrTran( cVALOR, '"', '' )
      AAdd( aRETU, cVALOR )
   ENDIF
   
   RETURN aRETU

// +--------------------------------------------------------------------
// + Parser Inteligente para Tipagem do CSV
// +--------------------------------------------------------------------
STATIC FUNCTION ParseFieldDefinition( cDef )
   LOCAL aParts, cName := "", cType := "C", nLen := 0, nDec := 0, cSec
   
   cDef := AllTrim( StrTran( cDef, '"', '' ) )
   aParts := hb_ATokens( cDef, "," )
   
   IF Len( aParts ) > 0
      cName := AllTrim( aParts[ 1 ] )
   ENDIF
   
   IF Len( aParts ) > 1
      cSec := Upper( AllTrim( aParts[ 2 ] ) )
      IF cSec $ "N,C,D,L,M"
         cType := cSec
         IF Len( aParts ) > 2
            nLen := Val( aParts[ 3 ] )
         ENDIF
         IF Len( aParts ) > 3
            nDec := Val( aParts[ 4 ] )
         ENDIF
      ELSE
         cType := "N"
         nLen  := Val( cSec )
         IF Len( aParts ) > 2
            nDec := Val( aParts[ 3 ] )
         ENDIF
      ENDIF
   ENDIF
   
   IF cType == "D" .AND. nLen == 0; nLen := 8; ENDIF
   IF cType == "L" .AND. nLen == 0; nLen := 1; ENDIF
   IF cType == "M" .AND. nLen == 0; nLen := 4; ENDIF
   
   RETURN { cName, cType, nLen, nDec }

// +--------------------------------------------------------------------
// + Conversão Lógica Robusta (Mod 5)
// +--------------------------------------------------------------------
STATIC FUNCTION StrLogicrdd( cVAL, lDEFAULT )
   IF ValType( lDEFAULT ) <> "L"
      lDEFAULT := .F.
   ENDIF
   cVal := AllTrim( cVal )
   
   SWITCH Upper( cVal )
   CASE ".T."
   CASE "TRUE"
   CASE "YES"
   CASE "SIM"
   CASE "ON"
   CASE "Y"
   CASE "1"
   CASE "T"
   CASE "S"
      RETURN .T.
   CASE ".F."
   CASE "FALSE"
   CASE "NO"
   CASE "NAO"
   CASE "OFF"
   CASE "N"
   CASE "0"
   CASE "F"
   CASE "<NULL>"
   CASE "NULL"
   CASE "NUL"
   CASE "NIL"
      RETURN .F.
   ENDSWITCH

   RETURN lDEFAULT

// +--------------------------------------------------------------------
// + Conversão de Data Inteligente (Mod 6)
// +--------------------------------------------------------------------
STATIC FUNCTION StrDateRdd( cVal )
   LOCAL dRet := CToD("")
   
   cVal := AllTrim( cVal )
   IF Empty( cVal ) .OR. cVal == "NULL" .OR. cVal == "0000-00-00" .OR. cVal == "00/00/0000"
      RETURN dRet
   ENDIF

   IF Len( cVal ) >= 10
      IF SubStr( cVal, 5, 1 ) $ "-/"
         // Formatos YYYY-MM-DD ou YYYY/MM/DD
         dRet := SToD( SubStr( cVal, 1, 4 ) + SubStr( cVal, 6, 2 ) + SubStr( cVal, 9, 2 ) )
      ELSEIF SubStr( cVal, 3, 1 ) $ "-/"
         // Formatos DD/MM/YYYY ou DD-MM-YYYY
         dRet := SToD( SubStr( cVal, 7, 4 ) + SubStr( cVal, 4, 2 ) + SubStr( cVal, 1, 2 ) )
      ENDIF
   ELSEIF Len( cVal ) == 8 .AND. IsDigit( cVal )
      // Formato puramente YYYYMMDD
      dRet := SToD( cVal )
   ELSE
      // Fallback para conversão padrão regional
      dRet := CToD( cVal )
   ENDIF

   RETURN dRet


// +--------------------------------------------------------------------
// + Metodos Internos do RDD
// +--------------------------------------------------------------------

STATIC FUNCTION FCSV_INIT( nRDD )
   HB_SYMBOL_UNUSED( nRDD )
   RETURN HB_SUCCESS

STATIC FUNCTION FCSV_NEW( pWA )
   LOCAL aWData := { F_ERROR, .F., .F., "", 0, "", {}, {} }
   USRRDD_AREADATA( pWA, aWData )
   RETURN HB_SUCCESS

STATIC FUNCTION FCSV_CREATE( nWA, aOpenInfo )
   LOCAL oError := ErrorNew()
   oError:GenCode     := EG_CREATE
   oError:SubCode     := 1004
   oError:Description := hb_langErrMsg( EG_CREATE ) + " (" + hb_langErrMsg( EG_UNSUPPORTED ) + ")"
   oError:FileName    := aOpenInfo[ UR_OI_NAME ]
   oError:CanDefault  := .T.
   UR_SUPER_ERROR( nWA, oError )
   RETURN HB_FAILURE

STATIC FUNCTION FCSV_OPEN( nWA, aOpenInfo )
   LOCAL cName, nMode, nHandle, aWData, aField, oError, nResult, cDelimDetectado
   LOCAL cHeaderLine, aNames, aParsedDef, nI, cLine, cPrimeiraLinha

   IF aOpenInfo[ UR_OI_ALIAS ] == NIL
      hb_FNameSplit( aOpenInfo[ UR_OI_NAME ], , @cName )
      aOpenInfo[ UR_OI_ALIAS ] := cName
   ENDIF

   nMode := iif( aOpenInfo[ UR_OI_SHARED ], FO_SHARED, FO_EXCLUSIVE ) + ;
            iif( aOpenInfo[ UR_OI_READONLY ], FO_READ, FO_READWRITE )

   cDelimDetectado := FDELIM( aOpenInfo[ UR_OI_NAME ], s_nReadSize )

   nHandle := FOpen( aOpenInfo[ UR_OI_NAME ], nMode )
   IF nHandle == F_ERROR
      oError := ErrorNew()
      oError:GenCode     := EG_OPEN
      oError:SubCode     := 1001
      oError:Description := hb_langErrMsg( EG_OPEN )
      oError:FileName    := aOpenInfo[ UR_OI_NAME ]
      oError:OsCode      := FError()
      oError:CanDefault  := .T.
      UR_SUPER_ERROR( nWA, oError )
      RETURN HB_FAILURE
   ENDIF

   // >>> DETECÇÃO AUTOMÁTICA INTELIGENTE <<<
   cPrimeiraLinha := Space( s_nReadSize )
   FRead( nHandle, @cPrimeiraLinha, s_nReadSize )
   FSeek( nHandle, 0, FS_SET ) // Retorna o ponteiro

   // Mod 2 e 3: Ajustar para Pipe ou Tab caso existam na 1ª linha
   IF "|" $ cPrimeiraLinha
      s_cFieldDelim := "|"
   ELSEIF Chr(9) $ cPrimeiraLinha
      s_cFieldDelim := Chr(9)
   ENDIF

   // Mod 4: Detecção super segura de Arquivo Tipado (Exige '","' p/ não confundir com dados)
   IF ( ",N," $ Upper( cPrimeiraLinha ) .OR. ",C," $ Upper( cPrimeiraLinha ) .OR. ",D," $ Upper( cPrimeiraLinha ) ) .AND. At( '","', cPrimeiraLinha ) > 0
      s_cFieldDelim  := ","
      s_lUseHeader   := .T.
      s_lUseTypedCSV := .T.
      s_lUseSplit    := .T.
   ENDIF

   aWData := USRRDD_AREADATA( nWA )
   aWData[ 1 ] := nHandle
   aWData[ 2 ] := .F.
   aWData[ 3 ] := .F.
   aWData[ 4 ] := cDelimDetectado
   aWData[ 5 ] := 0
   aWData[ 6 ] := ""
   aWData[ 7 ] := {}
   aWData[ 8 ] := {}

   // 1. SE O CABEÇALHO FOI PASSADO MANUALMENTE VIA MATRIZ
   IF Len( s_aManualHeader ) > 0
      UR_SUPER_SETFIELDEXTENT( nWA, Len( s_aManualHeader ) )
      FOR nI := 1 TO Len( s_aManualHeader )
         aField := Array( UR_FI_SIZE )
         IF s_lUseTypedCSV
            aParsedDef := ParseFieldDefinition( s_aManualHeader[ nI ] )
            aField[ UR_FI_NAME ]    := AllTrim( aParsedDef[ 1 ] )
            AAdd( aWData[ 8 ], { aParsedDef[ 1 ], aParsedDef[ 2 ], aParsedDef[ 3 ], aParsedDef[ 4 ] } )
            AAdd( aWData[ 7 ], aParsedDef[ 1 ] )
         ELSE
            aField[ UR_FI_NAME ]    := AllTrim( StrTran( s_aManualHeader[ nI ], '"', '' ) )
            AAdd( aWData[ 8 ], { aField[ UR_FI_NAME ], "C", 0, 0 } )
            AAdd( aWData[ 7 ], aField[ UR_FI_NAME ] )
         ENDIF
         
         aField[ UR_FI_TYPE ]    := "C"
         aField[ UR_FI_TYPEEXT ] := 0
         aField[ UR_FI_LEN ]     := 0
         aField[ UR_FI_DEC ]     := 0
         UR_SUPER_ADDFIELD( nWA, aField )
      NEXT
   ELSE
      // 2. LEITURA AUTOMÁTICA DO ARQUIVO CSV
      IF s_lUseHeader
         cHeaderLine := FREADLINE( nHandle, s_nReadSize, .T., cDelimDetectado )
         IF cHeaderLine <> '__FINAL__'
            IF s_lUseSplit
               aNames := SplitAspasRDD( cHeaderLine, s_cFieldDelim )
            ELSE
               aNames := hb_ATokens( cHeaderLine, s_cFieldDelim )
            ENDIF   
            
            UR_SUPER_SETFIELDEXTENT( nWA, Len( aNames ) )
            FOR nI := 1 TO Len( aNames )
               aField := Array( UR_FI_SIZE )
               
               IF s_lUseTypedCSV
                  aParsedDef := ParseFieldDefinition( aNames[ nI ] )
                  aField[ UR_FI_NAME ] := AllTrim( aParsedDef[ 1 ] )
                  AAdd( aWData[ 8 ], { aParsedDef[ 1 ], aParsedDef[ 2 ], aParsedDef[ 3 ], aParsedDef[ 4 ] } )
                  AAdd( aWData[ 7 ], aParsedDef[ 1 ] ) // Armazena apenas o nome limpo em aWData[7]
               ELSE
                  aField[ UR_FI_NAME ] := AllTrim( StrTran( aNames[ nI ], '"', '' ) )
                  AAdd( aWData[ 8 ], { aField[ UR_FI_NAME ], "C", 0, 0 } )
                  AAdd( aWData[ 7 ], aField[ UR_FI_NAME ] ) // Armazena apenas o nome limpo
               ENDIF
               
               aField[ UR_FI_TYPE ]    := "C"
               aField[ UR_FI_TYPEEXT ] := 0
               aField[ UR_FI_LEN ]     := 0
               aField[ UR_FI_DEC ]     := 0
               UR_SUPER_ADDFIELD( nWA, aField )
            NEXT
         ENDIF
      ENDIF

      IF !s_lUseHeader .OR. Len( aWData[ 7 ] ) == 0
         cLine := FREADLINE( nHandle, s_nReadSize, .T., cDelimDetectado )
         IF cLine <> '__FINAL__'
            IF s_lUseSplit
              aNames := SplitAspasRDD( cLine, s_cFieldDelim )
            ELSE
              aNames := hb_ATokens( cLine, s_cFieldDelim )
            ENDIF  
            UR_SUPER_SETFIELDEXTENT( nWA, Len( aNames ) )
            FOR nI := 1 TO Len( aNames )
               aField := Array( UR_FI_SIZE )
               aField[ UR_FI_NAME ]    := "CAMPO" + AllTrim( Str( nI ) )
               aField[ UR_FI_TYPE ]    := "C"
               aField[ UR_FI_TYPEEXT ] := 0
               aField[ UR_FI_LEN ]     := 0
               aField[ UR_FI_DEC ]     := 0
               UR_SUPER_ADDFIELD( nWA, aField )
               AAdd( aWData[ 8 ], { aField[ UR_FI_NAME ], "C", 0, 0 } )
               AAdd( aWData[ 7 ], aField[ UR_FI_NAME ] )
            NEXT
         ELSE
            UR_SUPER_SETFIELDEXTENT( nWA, 1 )
            aField := Array( UR_FI_SIZE )
            aField[ UR_FI_NAME ]    := "CAMPO1"
            aField[ UR_FI_TYPE ]    := "C"
            aField[ UR_FI_TYPEEXT ] := 0
            aField[ UR_FI_LEN ]     := 0
            aField[ UR_FI_DEC ]     := 0
            UR_SUPER_ADDFIELD( nWA, aField )
            AAdd( aWData[ 8 ], { "CAMPO1", "C", 0, 0 } )
            AAdd( aWData[ 7 ], "CAMPO1" )
         ENDIF
         FSeek( nHandle, 0, FS_SET )
         IF s_lUseHeader
            FREADLINE( nHandle, s_nReadSize, .T., cDelimDetectado )
         ENDIF
      ENDIF
   ENDIF

   nResult := UR_SUPER_OPEN( nWA, aOpenInfo )

   IF nResult == HB_SUCCESS
      FCSV_GOTOP( nWA )
   ENDIF

   RETURN nResult

STATIC FUNCTION FCSV_CLOSE( nWA )
   LOCAL aWData := USRRDD_AREADATA( nWA )
   IF aWData[ 1 ] >= 0
      FClose( aWData[ 1 ] )
      aWData[ 1 ] := F_ERROR
   ENDIF
   RETURN UR_SUPER_CLOSE( nWA )

STATIC FUNCTION FCSV_READNEXT( aWData )
   LOCAL cLine := FREADLINE( aWData[ 1 ], s_nReadSize, .T., aWData[ 4 ] )
   
   IF cLine == '__FINAL__'
      aWData[ 3 ] := .T.
      aWData[ 6 ] := ""
      RETURN HB_FAILURE
   ELSE
      aWData[ 3 ] := .F.
      aWData[ 6 ] := cLine
      aWData[ 5 ]++
      RETURN HB_SUCCESS
   ENDIF

   RETURN HB_FAILURE

// +--------------------------------------------------------------------
// + Obtenção de Valor do Campo (Agora com Inteligência Tipada - Mod 1)
// +--------------------------------------------------------------------
STATIC FUNCTION FCSV_GETVALUE( nWA, nField, xValue )
   LOCAL aWData := USRRDD_AREADATA( nWA )
   LOCAL aCols, cType, xRawVal

   IF aWData[ 3 ]
      xValue := ""
      RETURN HB_SUCCESS
   ENDIF

   IF Empty( s_cFieldDelim )
      xRawVal := aWData[ 6 ]
   ELSE
      IF s_lUseSplit
         aCols := SplitAspasRDD( aWData[ 6 ], s_cFieldDelim )
      ELSE
         aCols := hb_ATokens( aWData[ 6 ], s_cFieldDelim )
      ENDIF

      IF nField >= 1 .AND. Len( aCols ) > 0 .AND. nField <= Len( aCols )
         xRawVal := aCols[ nField ]
      ELSE
         xRawVal := ""
      ENDIF
   ENDIF

   // >>> APLICAÇÃO DA REGRA 1: RETORNO CONVERTIDO SE MATRIZ EXISTIR E PARÂMETRO ATIVO <<<
   IF s_lRetornaTipado .AND. Len( aWData[ 8 ] ) >= nField
      cType := aWData[ 8 ][ nField ][ 2 ] // Pega o tipo original (N, C, D, L, M) da matriz auxiliar
      
      DO CASE
         CASE cType == "N"
            xValue := Val( xRawVal )
         CASE cType == "D"
            xValue := StrDateRdd( xRawVal )
         CASE cType == "L"
            xValue := StrLogicrdd( xRawVal, .F. )
         OTHERWISE
            xValue := xRawVal // Para "C", "M" ou falhas, retorna o caractere original
      ENDCASE
   ELSE
      // Comportamento normal do RDD: Retorna caractere bruto
      xValue := xRawVal
   ENDIF

   RETURN HB_SUCCESS

STATIC FUNCTION FCSV_GOTOP( nWA )
   LOCAL aWData := USRRDD_AREADATA( nWA )
   
   FSeek( aWData[ 1 ], 0, FS_SET )
   
   IF Len( s_aManualHeader ) == 0
      IF s_lUseHeader
         FREADLINE( aWData[ 1 ], s_nReadSize, .T., aWData[ 4 ] )
      ENDIF
   ENDIF
   
   aWData[ 2 ] := .T.
   aWData[ 3 ] := .F.
   aWData[ 5 ] := 0
   
   FCSV_READNEXT( aWData )
   RETURN HB_SUCCESS

STATIC FUNCTION FCSV_GOBOTTOM( nWA )
   LOCAL aWData := USRRDD_AREADATA( nWA )
   
   FCSV_GOTOP( nWA )
   WHILE !aWData[ 3 ]
      IF FCSV_READNEXT( aWData ) == HB_FAILURE
         EXIT
      ENDIF
   ENDDO
   RETURN HB_SUCCESS

STATIC FUNCTION FCSV_SKIPRAW( nWA, nRecords )
   LOCAL aWData := USRRDD_AREADATA( nWA )
   LOCAL n

   IF nRecords == 0
      RETURN HB_SUCCESS
   ENDIF

   IF nRecords > 0
      FOR n := 1 TO nRecords
         IF aWData[ 3 ]
            EXIT
         ENDIF
         FCSV_READNEXT( aWData )
      NEXT
   ELSE
      n := aWData[ 5 ] + nRecords
      FCSV_GOTOP( nWA )
      IF n > 1
         FOR n := 1 TO n - 1
            IF aWData[ 3 ]
               EXIT
            ENDIF
            FCSV_READNEXT( aWData )
         NEXT
      ENDIF
   ENDIF

   aWData[ 2 ] := ( aWData[ 5 ] <= 1 )
   RETURN HB_SUCCESS

STATIC FUNCTION FCSV_GOTO( nWA, nRecord )
   LOCAL aWData := USRRDD_AREADATA( nWA )
   
   IF nRecord <= 1
      FCSV_GOTOP( nWA )
   ELSE
      FCSV_GOTOP( nWA )
      FCSV_SKIPRAW( nWA, nRecord - 1 )
   ENDIF
   RETURN HB_SUCCESS

STATIC FUNCTION FCSV_GOTOID( nWA, nRecord )
   RETURN FCSV_GOTO( nWA, nRecord )

STATIC FUNCTION FCSV_Bof( nWA, lBof )
   LOCAL aWData := USRRDD_AREADATA( nWA )
   lBof := aWData[ 2 ]
   RETURN HB_SUCCESS

STATIC FUNCTION FCSV_EOF( nWA, lEof )
   LOCAL aWData := USRRDD_AREADATA( nWA )
   lEof := aWData[ 3 ]
   RETURN HB_SUCCESS

STATIC FUNCTION FCSV_DELETED( nWA, lDeleted )
   HB_SYMBOL_UNUSED( nWA )
   lDeleted := .F.
   RETURN HB_SUCCESS

STATIC FUNCTION FCSV_RECID( nWA, nRecNo )
   LOCAL aWData := USRRDD_AREADATA( nWA )
   nRecNo := aWData[ 5 ]
   RETURN HB_SUCCESS

STATIC FUNCTION FCSV_RECCOUNT( nWA, nRecords )
   LOCAL aWData := USRRDD_AREADATA( nWA )
   LOCAL nHandle := aWData[ 1 ]
   LOCAL nPosAnt, nLines, cLine

   IF !s_lUseRecCount
      nRecords := 0
      RETURN HB_SUCCESS
   ENDIF

   nPosAnt := FSeek( nHandle, 0, FS_RELATIVE )
   nLines := 0

   FSeek( nHandle, 0, FS_SET )
   IF Len( s_aManualHeader ) == 0
      IF s_lUseHeader
         FREADLINE( nHandle, s_nReadSize, .T., aWData[ 4 ] )
      ENDIF
   ENDIF
   
   WHILE .T.
      cLine := FREADLINE( nHandle, s_nReadSize, .T., aWData[ 4 ] )
      IF cLine == '__FINAL__'
         EXIT
      ENDIF
      nLines++
   ENDDO
   
   FSeek( nHandle, nPosAnt, FS_SET )
   nRecords := nLines
   RETURN HB_SUCCESS

STATIC FUNCTION FCSV_FCOUNT( nWA, nFields )
   LOCAL aWData := USRRDD_AREADATA( nWA )
   LOCAL aCols

   IF s_lUseHeader .AND. Len( aWData[ 7 ] ) > 0
      nFields := Len( aWData[ 7 ] )
   ELSEIF !Empty( aWData[ 6 ] )
      IF s_lUseSplit
         aCols := SplitAspasRDD( aWData[ 6 ], s_cFieldDelim )
      ELSE
         aCols := hb_ATokens( aWData[ 6 ], s_cFieldDelim )
      ENDIF
      nFields := Len( aCols )
   ELSE
      nFields := 1
   ENDIF
   RETURN HB_SUCCESS

STATIC FUNCTION FCSV_RDDINFO( nIndex, cargo ) 
   Local xRet := NIL
   HB_SYMBOL_UNUSED( cargo )

   DO CASE
      CASE nIndex == RDDI_TABLEEXT
         xRet := ".csv"

      CASE nIndex == RDDI_MEMOEXT
         xRet := ""

      CASE nIndex == RDDI_ORDBAGEXT
         xRet := ""
   ENDCASE

RETURN xRet

STATIC FUNCTION FCSV_INFO( nWA, nItem, xArg )
   LOCAL xRet := NIL

   DO CASE
      CASE nItem == DBI_ISDBF
         xRet := .F.

      CASE nItem == DBI_CANPUTREC
         xRet := .F.

      OTHERWISE
         xRet := UR_SUPER_INFO( nWA, nItem, xArg )
   ENDCASE

RETURN xRet

FUNCTION FCSVRDD_GETFUNCTABLE( pFuncCount, pFuncTable, pSuperTable, nRddID )
   LOCAL cSuperRDD := NIL
   LOCAL aMyFunc[ UR_METHODCOUNT ]

   aMyFunc[ UR_INIT ]     := @FCSV_INIT()
   aMyFunc[ UR_NEW ]      := @FCSV_NEW()
   aMyFunc[ UR_CREATE ]   := @FCSV_CREATE()
   aMyFunc[ UR_OPEN ]     := @FCSV_OPEN()
   aMyFunc[ UR_CLOSE ]    := @FCSV_CLOSE()
   aMyFunc[ UR_BOF  ]     := @FCSV_Bof()
   aMyFunc[ UR_EOF  ]     := @FCSV_Eof()
   aMyFunc[ UR_DELETED ]  := @FCSV_DELETED()
   aMyFunc[ UR_SKIPRAW ]  := @FCSV_SKIPRAW()
   aMyFunc[ UR_GOTO ]     := @FCSV_GOTO()
   aMyFunc[ UR_GOTOID ]   := @FCSV_GOTOID()
   aMyFunc[ UR_GOTOP ]    := @FCSV_GOTOP()
   aMyFunc[ UR_GOBOTTOM ] := @FCSV_GOBOTTOM()
   aMyFunc[ UR_RECID ]    := @FCSV_RECID()
   aMyFunc[ UR_RECCOUNT ] := @FCSV_RECCOUNT()
   aMyFunc[ UR_GETVALUE ] := @FCSV_GETVALUE()
   aMyFunc[ UR_FIELDCOUNT ] := @FCSV_FCOUNT()
   aMyFunc[ UR_RDDINFO ]  := @FCSV_RDDINFO()
   aMyFunc[ UR_INFO ]     := @FCSV_INFO()

   RETURN USRRDD_GETFUNCTABLE( pFuncCount, pFuncTable, pSuperTable, nRddID, ;
      cSuperRDD, aMyFunc )

INIT PROCEDURE FCSVRDD_INIT()
   rddRegister( "FCSVRDD", RDT_FULL )
   RETURN