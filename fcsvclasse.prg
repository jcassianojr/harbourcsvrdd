/*
 * Classe: CSVClass
 * Objetivo: Leitura linha a linha de arquivos CSV com cursor DBF-like.
 * Integracao: FCSVRDD (Tipagem/Split) + Buffer Customizado + Cabecalho Manual.
 */

#include "hbclass.ch"
#include "fileio.ch"

CREATE CLASS CSVClass

   VAR cFile
   VAR nHandle
   VAR nStartDataByte
   VAR aStruct
   VAR nFields
   VAR nRecNo
   VAR cDelim           
   VAR cLineDelim       
   VAR lHasHeader
   VAR lTyped           
   VAR lUseSplit        
   VAR cCurrentLine     
   VAR lEof
   VAR lBof
   VAR dwMaxBytes       // Tamanho inicial do buffer (Padrao 1024)
   VAR aManualHeader    // Matriz de cabecalho injetada manualmente
   VAR nBOMSize

   // Assinatura atualizada com todos os parametros do RDD
   METHOD New( cFileName, cDelimiter, lHeader, lRetornaTipado, lSplit, cLineDelimiter, aManualHeader, nReadSize )
   METHOD Open()
   METHOD Close()
   METHOD GoTop()
   METHOD GoBottom()
   METHOD Skip( nRows )
   METHOD GoTo( nRec )
   METHOD Eof()         INLINE ::lEof
   METHOD Bof()         INLINE ::lBof
   METHOD RecNo()       INLINE ::nRecNo
   METHOD LastRec()

   METHOD FieldName( nFieldPos )
   METHOD FieldPos( cFieldName )
   METHOD FieldGet( nFieldPos )
   METHOD GetRow()

   // Motores Internos
   METHOD ReadLineCustom()
   METHOD DetectDelimiter()
   METHOD DetectLineDelimiter()
   METHOD SplitCSV( cLine )
   METHOD SplitAspas( cLine, cSep )
   METHOD ParseFieldDefinition( cDef )
   METHOD StrLogic( cVal, lDefault )
   METHOD StrDate( xData )
   METHOD GetLine()
   METHOD GetStructOriginal() INLINE ::aStruct

ENDCLASS

METHOD New( cFileName, cDelimiter, lHeader, lRetornaTipado, lSplit, cLineDelimiter, aManualHeader, nReadSize ) CLASS CSVClass
   ::cFile         := cFileName
   ::cDelim        := hb_DefaultValue( cDelimiter, "" )
   ::lHasHeader    := hb_DefaultValue( lHeader, .T. )
   ::lTyped        := hb_DefaultValue( lRetornaTipado, .F. )
   ::lUseSplit     := hb_DefaultValue( lSplit, .F. )
   ::cLineDelim    := hb_DefaultValue( cLineDelimiter, "" )
   ::aManualHeader := hb_DefaultValue( aManualHeader, {} )
   ::dwMaxBytes    := hb_DefaultValue( nReadSize, 1024 ) // Alterado para 1024 conforme regra do RDD //[cite: 3]
   
   ::nHandle        := F_ERROR
   ::nStartDataByte := 0
   ::aStruct        := {}
   ::nFields        := 0
   ::nRecNo         := 0
   ::cCurrentLine   := ""
   ::lEof           := .F.
   ::lBof           := .T.
   ::nBOMSize       := 0
RETURN Self

// +--------------------------------------------------------------------
// + Retorna o registro atual em formato de string/linha bruta original
// +--------------------------------------------------------------------
METHOD GetLine() CLASS CSVClass
   IF ::nRecNo < 1 .OR. ::lEof
      RETURN ""
   ENDIF
   // Retorna exatamente a linha crua como foi lida do disco
   RETURN ::cCurrentLine

METHOD Open() CLASS CSVClass
   LOCAL cHeaderLine, aNames, nI, aDef, cField

   ::nHandle := FOpen( ::cFile, FO_READ + FO_SHARED )
   IF ::nHandle == F_ERROR
      RETURN .F.
   ENDIF

   IF Empty( ::cLineDelim )
      ::cLineDelim := ::DetectLineDelimiter()
   ENDIF

   IF Empty( ::cDelim )
      ::cDelim := ::DetectDelimiter()
   ENDIF

  // FSeek( ::nHandle, 0, FS_SET )
   FSeek( ::nHandle, ::nBOMSize, FS_SET )

   // 1. SE O CABEÇALHO FOI PASSADO MANUALMENTE VIA MATRIZ //[cite: 3]
   IF Len( ::aManualHeader ) > 0
      ::nFields := Len( ::aManualHeader )
      
      FOR nI := 1 TO ::nFields
         IF ::lTyped
            aDef := ::ParseFieldDefinition( ::aManualHeader[ nI ] )
            AAdd( ::aStruct, { aDef[ 1 ], aDef[ 2 ], aDef[ 3 ], aDef[ 4 ] } )
         ELSE
            cField := Upper( AllTrim( StrTran( ::aManualHeader[ nI ], '"', '' ) ) )
            AAdd( ::aStruct, { cField, "C", 0, 0 } )
         ENDIF
      NEXT
      
      IF ::lHasHeader
         ::ReadLineCustom() // Descarta a primeira linha fisica do arquivo pois usara o manual
      ENDIF

   ELSE
      // 2. LEITURA AUTOMATICA DO ARQUIVO CSV
      cHeaderLine := ::ReadLineCustom()
      aNames := ::SplitCSV( cHeaderLine )
      ::nFields := Len( aNames )

      FOR nI := 1 TO ::nFields
         IF ::lHasHeader .AND. ::lTyped
            aDef := ::ParseFieldDefinition( aNames[ nI ] ) 
            AAdd( ::aStruct, { aDef[ 1 ], aDef[ 2 ], aDef[ 3 ], aDef[ 4 ] } )
         ELSEIF ::lHasHeader
            cField := Upper( AllTrim( StrTran( aNames[ nI ], '"', '' ) ) ) 
            AAdd( ::aStruct, { cField, "C", 0, 0 } )
         ELSE
            AAdd( ::aStruct, { "CAMPO" + AllTrim( Str( nI ) ), "C", 0, 0 } )
         ENDIF
      NEXT

      IF !::lHasHeader
         //FSeek( ::nHandle, 0, FS_SET ) // Rebobina pois a primeira linha ja era dado
         FSeek( ::nHandle, ::nBOMSize, FS_SET )
      ENDIF
   ENDIF

   ::nStartDataByte := FSeek( ::nHandle, 0, FS_RELATIVE )
   ::GoTop()
RETURN .T.

METHOD Close() CLASS CSVClass
   IF ::nHandle != F_ERROR
      FClose( ::nHandle )
      ::nHandle := F_ERROR
   ENDIF
   ::aStruct := {}
RETURN NIL

METHOD ReadLineCustom() CLASS CSVClass
   LOCAL cBuffer, nRead, nPos, cResult, nStartPos

   IF ::nHandle == F_ERROR .OR. ::lEof
      RETURN ""
   ENDIF

   nStartPos := FSeek( ::nHandle, 0, FS_RELATIVE )
   cBuffer   := Space( ::dwMaxBytes )
   nRead     := FRead( ::nHandle, @cBuffer, ::dwMaxBytes )

   IF nRead == 0
      ::lEof := .T.
      RETURN ""
   ENDIF

   cBuffer := Left( cBuffer, nRead ) 
   nPos    := At( ::cLineDelim, cBuffer ) 

   IF nPos > 0
      cResult := Left( cBuffer, nPos - 1 )
      FSeek( ::nHandle, nStartPos + nPos + Len( ::cLineDelim ) - 1, FS_SET )
   ELSE
      cResult := cBuffer
      IF nRead < ::dwMaxBytes
         ::lEof := .T.
      ENDIF
   ENDIF
RETURN cResult

METHOD DetectLineDelimiter() CLASS CSVClass
   LOCAL cHeader := Space( ::dwMaxBytes )
   LOCAL nBytes, cRet := hb_osNewLine()

   FSeek( ::nHandle, 0, FS_SET )
   nBytes := FRead( ::nHandle, @cHeader, ::dwMaxBytes ) 

   IF nBytes > 0
      cHeader := Left( cHeader, nBytes )
      
      // 1. Lógica do FDELIM adaptada: Detecta e guarda o tamanho do BOM (apenas no início exato)
      IF Left( cHeader, 3 ) == Chr( 239 ) + Chr( 187 ) + Chr( 191 ) // UTF-8
         ::nBOMSize := 3
      ELSEIF Left( cHeader, 2 ) == Chr( 255 ) + Chr( 254 ) // Unicode (UTF-16 LE)
         ::nBOMSize := 2
      ELSEIF Left( cHeader, 2 ) == Chr( 254 ) + Chr( 255 ) // Unicode (UTF-16 BE)
         ::nBOMSize := 2
      ELSE
         ::nBOMSize := 0
      ENDIF

      // 2. Continua a busca pela quebra de linha real
      IF Chr(13) + Chr(10) $ cHeader
         cRet := Chr(13) + Chr(10) 
      ELSEIF Chr(10) $ cHeader
         cRet := Chr(10) 
      ELSEIF Chr(13) $ cHeader
         cRet := Chr(13) 
      ELSEIF "@@" $ cHeader
         cRet := "@@" 
      ENDIF
   ENDIF
   
   // Retorna o ponteiro para logo APÓS o BOM, em vez do byte 0 absoluto
   FSeek( ::nHandle, ::nBOMSize, FS_SET ) 
RETURN cRet

METHOD DetectDelimiter() CLASS CSVClass
   LOCAL cHeader := Space( 256 )
   LOCAL nBytes, cRet := ";"

   FSeek( ::nHandle, 0, FS_SET )
   nBytes := FRead( ::nHandle, @cHeader, 256 ) 

   IF nBytes > 0
      cHeader := Left( cHeader, nBytes )
      IF Chr(9) $ cHeader
         cRet := Chr(9) 
      ELSEIF "|" $ cHeader
         cRet := "|" 
      ELSEIF "," $ cHeader
         cRet := "," 
      ENDIF
   ENDIF
   FSeek( ::nHandle, 0, FS_SET ) 
RETURN cRet

METHOD GoTop() CLASS CSVClass
   IF ::nHandle != F_ERROR
      FSeek( ::nHandle, ::nStartDataByte, FS_SET ) 
      ::lEof := .F.
      ::lBof := .T.
      ::nRecNo := 0
      ::Skip( 1 )
   ENDIF
RETURN NIL

METHOD GoBottom() CLASS CSVClass
   WHILE !::lEof
      ::Skip( 1 )
   ENDDO
RETURN NIL

METHOD Skip( nRows ) CLASS CSVClass
   LOCAL nI
   IF ValType( nRows ) <> "N"; nRows := 1; ENDIF

   IF nRows > 0
      FOR nI := 1 TO nRows
         IF ::lEof; EXIT; ENDIF
         ::cCurrentLine := ::ReadLineCustom()
         IF !::lEof
            ::nRecNo++
            ::lBof := .F.
         ENDIF
      NEXT
   ELSEIF nRows < 0
      ::GoTo( ::nRecNo + nRows )
   ENDIF
RETURN NIL

METHOD GoTo( nRec ) CLASS CSVClass
   LOCAL nI
   IF nRec < 1
      ::GoTop()
   ELSEIF nRec < ::nRecNo
      ::GoTop()
      FOR nI := 1 TO nRec - 1
         ::Skip( 1 )
      NEXT
   ELSEIF nRec > ::nRecNo
      ::Skip( nRec - ::nRecNo )
   ENDIF
RETURN NIL

METHOD LastRec() CLASS CSVClass
   LOCAL nPosAtual, nLastRec := 0
   IF ::nHandle != F_ERROR
      nPosAtual := FSeek( ::nHandle, 0, FS_RELATIVE )
      FSeek( ::nHandle, ::nStartDataByte, FS_SET )
      ::lEof := .F.
      WHILE !::lEof
         ::ReadLineCustom()
         IF !::lEof; nLastRec++; ENDIF
      ENDDO
      FSeek( ::nHandle, nPosAtual, FS_SET )
      ::lEof := .F.
   ENDIF
RETURN nLastRec

METHOD FieldName( nFieldPos ) CLASS CSVClass
   IF nFieldPos >= 1 .AND. nFieldPos <= ::nFields
      RETURN ::aStruct[ nFieldPos, 1 ]
   ENDIF
RETURN ""

METHOD FieldPos( cFieldName ) CLASS CSVClass
   cFieldName := Upper( AllTrim( cFieldName ) )
   RETURN AScan( ::aStruct, {|x| x[ 1 ] == cFieldName } )

METHOD FieldGet( nFieldPos ) CLASS CSVClass
   LOCAL aRow, xRawVal, xVal, cType

   IF ::nRecNo < 1 .OR. ::lEof .OR. nFieldPos < 1 .OR. nFieldPos > ::nFields
      RETURN NIL
   ENDIF

   aRow := ::SplitCSV( ::cCurrentLine )
   
   IF nFieldPos <= Len( aRow )
      xRawVal := aRow[ nFieldPos ]
   ELSE
      xRawVal := ""
   ENDIF

   IF ::lTyped
      cType := ::aStruct[ nFieldPos, 2 ]
      DO CASE
         CASE cType == "N"
            xVal := Val( xRawVal )
         CASE cType == "D"
            xVal := ::StrDate( xRawVal ) 
         CASE cType == "T" .OR. cType == "@"
               xVal := UniversalDateTime( xRawVal )   
         CASE cType == "L"
            xVal := ::StrLogic( xRawVal, .F. ) 
         OTHERWISE
            xVal := xRawVal
      ENDCASE
   ELSE
      xVal := xRawVal
   ENDIF

RETURN xVal

METHOD GetRow() CLASS CSVClass
   LOCAL aRow := {}, nI
   IF !::lEof
      FOR nI := 1 TO ::nFields
         AAdd( aRow, ::FieldGet( nI ) )
      NEXT
   ENDIF
RETURN aRow

METHOD SplitCSV( cLine ) CLASS CSVClass
   LOCAL aRet := {}
   IF Empty( ::cDelim )
      AAdd( aRet, cLine )
   ELSEIF ::lUseSplit
      aRet := ::SplitAspas( cLine, ::cDelim ) 
   ELSE
      aRet := hb_ATokens( cLine, ::cDelim ) 
   ENDIF
RETURN aRet

METHOD SplitAspas( cLINHA, cSEPCAMPOS ) CLASS CSVClass
   LOCAL aRETU := {}, cVALOR := "", lInQuotes := .F., nI := 1, nLen, cChar
   LOCAL lFirstField := .T.
   
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

METHOD ParseFieldDefinition( cDef ) CLASS CSVClass
   LOCAL aParts, cName := "", cType := "C", nLen := 0, nDec := 0, cSec
   
   cDef := AllTrim( StrTran( cDef, '"', '' ) ) 
   aParts := hb_ATokens( cDef, "," ) 
   
   IF Len( aParts ) > 0; cName := AllTrim( aParts[ 1 ] ); ENDIF
   
   IF Len( aParts ) > 1
      cSec := Upper( AllTrim( aParts[ 2 ] ) )
      IF cSec $ "N,C,D,L,M"
         cType := cSec 
         IF Len( aParts ) > 2; nLen := Val( aParts[ 3 ] ); ENDIF
         IF Len( aParts ) > 3; nDec := Val( aParts[ 4 ] ); ENDIF
      ELSE
         cType := "N" 
         nLen  := Val( cSec )
         IF Len( aParts ) > 2; nDec := Val( aParts[ 3 ] ); ENDIF
      ENDIF
   ENDIF
   
   IF cType == "D" .AND. nLen == 0; nLen := 8; ENDIF
   IF cType == "L" .AND. nLen == 0; nLen := 1; ENDIF
   IF cType == "M" .AND. nLen == 0; nLen := 4; ENDIF
   
RETURN { cName, cType, nLen, nDec }

METHOD StrLogic( cVal, lDefault ) CLASS CSVClass
   IF ValType( lDefault ) <> "L"; lDefault := .F.; ENDIF
   cVal := AllTrim( cVal )
   
   SWITCH Upper( cVal )
   CASE ".T."; CASE "TRUE"; CASE "YES"; CASE "SIM"; CASE "ON"; CASE "Y"; CASE "1"; CASE "T"; CASE "S"
      RETURN .T. 
   CASE ".F."; CASE "FALSE"; CASE "NO"; CASE "NAO"; CASE "OFF"; CASE "N"; CASE "0"; CASE "F"; CASE "<NULL>"; CASE "NULL"
      RETURN .F. 
   ENDSWITCH
RETURN lDefault

METHOD StrDate( xData ) CLASS CSVClass

LOCAL dRet := CToD( "" )
   LOCAL cTemp, aParts 
   LOCAL i, nMes, cMes, cAno, cDia, nDia, nAno, cMesStr
   LOCAL cCleanData
   
   // Matrizes independentes pela clareza e velocidade nativa do AScan
   LOCAL aMonthsEN := { "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" }
   LOCAL aMonthsPT := { "JAN", "FEV", "MAR", "ABR", "MAI", "JUN", "JUL", "AGO", "SET", "OUT", "NOV", "DEZ" }

   IF ValType( xData ) == "D"
      RETURN xData
   ENDIF

   IF ValType( xData ) <> "C" .OR. Empty( xData )
      RETURN dRet
   ENDIF

// Limpa uma única vez para otimizar os testes
   cCleanData := Upper( AllTrim( xData ) )

   // Barreira imediata contra literais nulos/vazios
   IF cCleanData == "NULL" .OR. cCleanData == "NIL" .OR. cCleanData == "<NULL>" .OR. cCleanData == "NUL" .OR. cCleanData == "/  /" .OR. cCleanData == "-  -"
      RETURN dRet
   ENDIF
   
   cTemp := AllTrim( xData )

   // -------------------------------------------------------------------------
   // Suporte a Formatos HTTP-date e Logs (Inglês e Português)
   // -------------------------------------------------------------------------
   cTemp := StrTran( cTemp, ",", " " )
   cTemp := StrTran( cTemp, "-", " " )

   DO WHILE "  " $ cTemp
      cTemp := StrTran( cTemp, "  ", " " )
   ENDDO

   aParts := hb_ATokens( AllTrim( cTemp ), " " )

   IF Len( aParts ) >= 4
      FOR i := 1 TO Len( aParts )
         cMesStr := Upper( Left( aParts[ i ], 3 ) )
         
         // 1. Busca primeiro em Inglês
         nMes := AScan( aMonthsEN, cMesStr )
         
         // 2. Se não encontrar, tenta em Português
         IF nMes == 0
            nMes := AScan( aMonthsPT, cMesStr )
         ENDIF
         
         // Se encontrou o mês, processa
         IF nMes > 0
            cMes := StrZero( nMes, 2 )
            
            // Extrai o Dia e o Ano baseado na posição do Mês (ANSI C vs RFC)
            IF i == 2 .AND. Len( aParts ) >= 5 // ANSI C asctime
               cDia := StrZero( Val( aParts[ 3 ] ), 2 )
               cAno := aParts[ 5 ]
            ELSEIF i == 3 // RFC 1123 / RFC 850
               cDia := StrZero( Val( aParts[ 2 ] ), 2 )
               cAno := aParts[ 4 ]
               
               IF Len( cAno ) == 2
                  nAno := Val( cAno )
                  cAno := iif( nAno < 50, "20" + cAno, "19" + cAno )
               ENDIF
            ELSE
               LOOP 
            ENDIF
            
            nDia := Val( cDia )
            nAno := Val( cAno )
            
            IF nDia >= 1 .AND. nDia <= 31 .AND. nAno >= 1000 .AND. Len( cAno ) == 4
               dRet := SToD( cAno + cMes + cDia )
               IF !Empty( dRet )
                  RETURN dRet
               ENDIF
            ENDIF
         ENDIF
      NEXT
   ENDIF

   // -------------------------------------------------------------------------
   // Fallback Original para Bancos de Dados (YYYY-MM-DD, DD/MM/YYYY, etc.)
   // -------------------------------------------------------------------------
   cTemp := AllTrim( xData ) // Restaura a string original limpa para o fallback
   cTemp := StrTran( cTemp, "-", "/" ) 
   cTemp := StrTran( cTemp, ".", "/" ) 
   aParts := hb_ATokens( cTemp, "/" ) 

   IF Len( aParts ) == 3
      IF Len( aParts[ 1 ] ) == 4
         cAno := aParts[ 1 ]
         cMes := StrZero( Val( aParts[ 2 ] ), 2 ) 
         cDia := StrZero( Val( aParts[ 3 ] ), 2 )
      ELSE
         cDia := StrZero( Val( aParts[ 1 ] ), 2 ) 
         cMes := StrZero( Val( aParts[ 2 ] ), 2 )
         cAno := aParts[ 3 ]
         IF Len( cAno ) == 2
            nAno := Val( cAno )
            cAno := iif( nAno < 50, "20" + cAno, "19" + cAno ) 
         ENDIF
      ENDIF
      IF cAno + cMes + cDia == "00000000"
         RETURN CToD( "" )
      ENDIF 
      dRet := SToD( cAno + cMes + cDia ) 
      RETURN iif( Empty( dRet ), CToD( "" ), dRet )
   ELSE
      IF Len( cTemp ) == 8
         IF Val( Left( cTemp, 4 ) ) > 1900
            dRet := SToD( cTemp ) 
         ELSE
            dRet := SToD( Right( cTemp, 4 ) + SubStr( cTemp, 3, 2 ) + Left( cTemp, 2 ) ) 
         ENDIF
      ELSEIF Len( cTemp ) == 6
         nAno := Val( Right( cTemp, 2 ) )
         cAno := iif( nAno < 50, "20" + Right( cTemp, 2 ), "19" + Right( cTemp, 2 ) ) 
         dRet := SToD( cAno + SubStr( cTemp, 3, 2 ) + Left( cTemp, 2 ) ) 
      ELSE
         dRet := CToD( xData ) 
      ENDIF
   ENDIF
RETURN dRet

 // +--------------------------------------------------------------------
// +  Função: UniversalDateTime
// +  Objetivo: Tratar datas complexas mantendo e corrigindo o horário
// +  Retorna: Timestamp nativo (T) de alta precisão
// +--------------------------------------------------------------------
STATIC FUNCTION UniversalDateTime( xData )

   LOCAL cStr, cDataLimpa, aParts, i, dData
   LOCAL cTime := "00:00:00"
   LOCAL nHour := 0, nMin := 0, nSec := 0

   // 1. Já é Data ou Timestamp? Trata a conversão direta
   IF ValType( xData ) == "T"
      RETURN xData
   ELSEIF ValType( xData ) == "D"
      RETURN hb_DateTime( Year(xData), Month(xData), Day(xData) )
   ENDIF

   // 2. Barreira para nulos ou variáveis não suportadas
   IF ValType( xData ) <> "C" .OR. Empty( xData )
      RETURN hb_DateTime( 0, 0, 0 )
   ENDIF

   // 3. Limpa espaços e conserta erros como ";" ou tags ISO "T"
   cStr := AllTrim( xData )
   cStr := StrTran( cStr, ";", ":" )
   cStr := StrTran( cStr, "T", " " )

   aParts := hb_ATokens( cStr, " " )
   cDataLimpa := ""

   // 4. Caçador de Horários
   FOR i := 1 TO Len( aParts )
      IF ":" $ aParts[i] .AND. Val( StrTran( aParts[i], ":", "" ) ) >= 0
         cTime := aParts[i] // Isola apenas a hora encontrada
      ELSE
         cDataLimpa += aParts[i] + " " // Reconstrói string base só da data
      ENDIF
   NEXT

   cDataLimpa := AllTrim( cDataLimpa )
   
   // 5. Utiliza o motor otimizado para extrair o calendário válido
   dData := StrDate( cDataLimpa )

   // Fallback se a rotina retornar vazio, checa direto via Harbour CToD
   IF Empty( dData ) .AND. !Empty( CToD( cDataLimpa ) )
      dData := CToD( cDataLimpa )
   ENDIF

   IF Empty( dData )
      RETURN hb_DateTime( 0, 0, 0 )
   ENDIF

   // 6. Separa e converte as partes do Horário
   aParts := hb_ATokens( cTime, ":" )
   IF Len( aParts ) >= 1; nHour := Val( aParts[1] ); ENDIF
   IF Len( aParts ) >= 2; nMin  := Val( aParts[2] ); ENDIF
   IF Len( aParts ) >= 3; nSec  := Val( aParts[3] ); ENDIF

   // 7. Retorna o Objeto Timestamp Oficial
   RETURN hb_DateTime( Year( dData ), Month( dData ), Day( dData ), nHour, nMin, nSec ) 
   