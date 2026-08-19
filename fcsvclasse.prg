/*
 * Classe: CSVClass
 * Objetivo: Leitura linha a linha de arquivos CSV com cursor DBF-like.
 * Integracao: FCSVRDD (Tipagem/Split) + TextDBServer (ReadLineCustom / Delimitadores).
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
   VAR dwMaxBytes       // Tamanho maximo do bloco de leitura

   // Assinatura rigorosamente unificada
   METHOD New( cFileName, cDelimiter, lHeader, lRetornaTipado, lSplit, cLineDelimiter )
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

ENDCLASS

METHOD New( cFileName, cDelimiter, lHeader, lRetornaTipado, lSplit, cLineDelimiter ) CLASS CSVClass
   ::cFile      := cFileName
   ::cDelim     := hb_DefaultValue( cDelimiter, "" )
   ::lHasHeader := hb_DefaultValue( lHeader, .T. )
   ::lTyped     := hb_DefaultValue( lRetornaTipado, .F. )
   ::lUseSplit  := hb_DefaultValue( lSplit, .F. )
   ::cLineDelim := hb_DefaultValue( cLineDelimiter, "" )
   ::dwMaxBytes := 4096 // Equivalente ao alocador de memoria do VO //[cite: 2]
   
   ::nHandle        := F_ERROR
   ::nStartDataByte := 0
   ::aStruct        := {}
   ::nFields        := 0
   ::nRecNo         := 0
   ::cCurrentLine   := ""
   ::lEof           := .F.
   ::lBof           := .T.
RETURN Self

METHOD Open() CLASS CSVClass
   LOCAL cHeaderLine, aNames, nI, aDef, cField

   ::nHandle := FOpen( ::cFile, FO_READ + FO_SHARED )
   IF ::nHandle == F_ERROR
      RETURN .F.
   ENDIF

   // Autodeteccao de Delimitadores baseada no VO //[cite: 2]
   IF Empty( ::cLineDelim )
      ::cLineDelim := ::DetectLineDelimiter()
   ENDIF

   IF Empty( ::cDelim )
      ::cDelim := ::DetectDelimiter()
   ENDIF

   // Garante ponteiro no inicio antes de ler header
   FSeek( ::nHandle, 0, FS_SET )

   // Processa o Header
   cHeaderLine := ::ReadLineCustom()
   aNames := ::SplitCSV( cHeaderLine )
   ::nFields := Len( aNames )

   FOR nI := 1 TO ::nFields
      IF ::lHasHeader .AND. ::lTyped
         aDef := ::ParseFieldDefinition( aNames[ nI ] ) //[cite: 3]
         AAdd( ::aStruct, { aDef[ 1 ], aDef[ 2 ], aDef[ 3 ], aDef[ 4 ] } )
      ELSEIF ::lHasHeader
         cField := Upper( AllTrim( StrTran( aNames[ nI ], '"', '' ) ) ) //[cite: 3]
         AAdd( ::aStruct, { cField, "C", 0, 0 } )
      ELSE
         AAdd( ::aStruct, { "CAMPO" + AllTrim( Str( nI ) ), "C", 0, 0 } )
      ENDIF
   NEXT

   IF ::lHasHeader
      // Salva a posicao EXATA logo apos o Header para rebobinar dps //[cite: 2]
      ::nStartDataByte := FSeek( ::nHandle, 0, FS_RELATIVE )
   ELSE
      // Se não tem header, rebobina para que o GoTop pegue a 1ª linha como dado
      ::nStartDataByte := 0
   ENDIF

   ::GoTop()
RETURN .T.

METHOD Close() CLASS CSVClass
   IF ::nHandle != F_ERROR
      FClose( ::nHandle )
      ::nHandle := F_ERROR
   ENDIF
   ::aStruct := {}
RETURN NIL

// Logica original de Leitura Fisica (Portado do TextDBServer) //[cite: 2]
METHOD ReadLineCustom() CLASS CSVClass
   LOCAL cBuffer, nRead, nPos, cResult, nStartPos

   IF ::nHandle == F_ERROR .OR. ::lEof
      RETURN ""
   ENDIF

   // Guarda onde o ponteiro comecou a ler //[cite: 2]
   nStartPos := FSeek( ::nHandle, 0, FS_RELATIVE )
   cBuffer   := Space( ::dwMaxBytes )
   nRead     := FRead( ::nHandle, @cBuffer, ::dwMaxBytes )

   IF nRead == 0
      ::lEof := .T.
      RETURN ""
   ENDIF

   cBuffer := Left( cBuffer, nRead ) //[cite: 2]
   nPos    := At( ::cLineDelim, cBuffer ) //[cite: 2]

   IF nPos > 0
      // Corta ANTES do delimitador //[cite: 2]
      cResult := Left( cBuffer, nPos - 1 )
      // REBOBINA O ARQUIVO: exato byte pos delimitador //[cite: 2]
      FSeek( ::nHandle, nStartPos + nPos + Len( ::cLineDelim ) - 1, FS_SET )
   ELSE
      cResult := cBuffer
      IF nRead < ::dwMaxBytes
         ::lEof := .T.
      ENDIF
   ENDIF
RETURN cResult

METHOD DetectLineDelimiter() CLASS CSVClass
   LOCAL cHeader := Space( 1024 )
   LOCAL nBytes, cRet := hb_osNewLine()

   FSeek( ::nHandle, 0, FS_SET )
   nBytes := FRead( ::nHandle, @cHeader, 1024 ) //[cite: 2]

   IF nBytes > 0
      cHeader := Left( cHeader, nBytes )
      IF Chr(13) + Chr(10) $ cHeader
         cRet := Chr(13) + Chr(10) //[cite: 2]
      ELSEIF Chr(10) $ cHeader
         cRet := Chr(10) //[cite: 2]
      ELSEIF Chr(13) $ cHeader
         cRet := Chr(13) //[cite: 2]
      ELSEIF "@@" $ cHeader
         cRet := "@@" //[cite: 2]
      ENDIF
   ENDIF
   FSeek( ::nHandle, 0, FS_SET ) //[cite: 2]
RETURN cRet

METHOD DetectDelimiter() CLASS CSVClass
   LOCAL cHeader := Space( 256 )
   LOCAL nBytes, cRet := ";"

   FSeek( ::nHandle, 0, FS_SET )
   nBytes := FRead( ::nHandle, @cHeader, 256 ) //[cite: 2]

   IF nBytes > 0
      cHeader := Left( cHeader, nBytes )
      IF Chr(9) $ cHeader
         cRet := Chr(9) //[cite: 2]
      ELSEIF "|" $ cHeader
         cRet := "|" //[cite: 2]
      ELSEIF "," $ cHeader
         cRet := "," //[cite: 2]
      ENDIF
   ENDIF
   FSeek( ::nHandle, 0, FS_SET ) //[cite: 2]
RETURN cRet

METHOD GoTop() CLASS CSVClass
   IF ::nHandle != F_ERROR
      FSeek( ::nHandle, ::nStartDataByte, FS_SET ) //[cite: 2]
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
            xVal := ::StrDate( xRawVal ) //[cite: 3]
         CASE cType == "L"
            xVal := ::StrLogic( xRawVal, .F. ) //[cite: 3]
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
      aRet := ::SplitAspas( cLine, ::cDelim ) //[cite: 3]
   ELSE
      aRet := hb_ATokens( cLine, ::cDelim ) //[cite: 3]
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
            cVALOR := SubStr( cVALOR, 2, Len( cVALOR ) - 2 ) //[cite: 3]
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
   
   cDef := AllTrim( StrTran( cDef, '"', '' ) ) //[cite: 3]
   aParts := hb_ATokens( cDef, "," ) //[cite: 3]
   
   IF Len( aParts ) > 0; cName := AllTrim( aParts[ 1 ] ); ENDIF
   
   IF Len( aParts ) > 1
      cSec := Upper( AllTrim( aParts[ 2 ] ) )
      IF cSec $ "N,C,D,L,M"
         cType := cSec //[cite: 3]
         IF Len( aParts ) > 2; nLen := Val( aParts[ 3 ] ); ENDIF
         IF Len( aParts ) > 3; nDec := Val( aParts[ 4 ] ); ENDIF
      ELSE
         cType := "N" //[cite: 3]
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
      RETURN .T. //[cite: 3]
   CASE ".F."; CASE "FALSE"; CASE "NO"; CASE "NAO"; CASE "OFF"; CASE "N"; CASE "0"; CASE "F"; CASE "<NULL>"; CASE "NULL"
      RETURN .F. //[cite: 3]
   ENDSWITCH
RETURN lDefault

METHOD StrDate( xData ) CLASS CSVClass
   LOCAL dRet := CToD( "" ), cTemp, aParts, cAno, cMes, cDia, nAno

   IF ValType( xData ) == "D"; RETURN xData; ENDIF //[cite: 3]
   IF ValType( xData ) <> "C" .OR. Empty( xData ) .OR. xData == "NULL"; RETURN dRet; ENDIF //[cite: 3]

   xData := AllTrim( xData )
   cTemp := StrTran( xData, "-", "/" ) //[cite: 3]
   cTemp := StrTran( cTemp, ".", "/" ) //[cite: 3]
   aParts := hb_ATokens( cTemp, "/" ) //[cite: 3]

   IF Len( aParts ) == 3
      IF Len( aParts[ 1 ] ) == 4
         cAno := aParts[ 1 ]
         cMes := StrZero( Val( aParts[ 2 ] ), 2 ) //[cite: 3]
         cDia := StrZero( Val( aParts[ 3 ] ), 2 )
      ELSE
         cDia := StrZero( Val( aParts[ 1 ] ), 2 ) //[cite: 3]
         cMes := StrZero( Val( aParts[ 2 ] ), 2 )
         cAno := aParts[ 3 ]
         IF Len( cAno ) == 2
            nAno := Val( cAno )
            cAno := iif( nAno < 50, "20" + cAno, "19" + cAno ) //[cite: 3]
         ENDIF
      ENDIF
      IF cAno + cMes + cDia == "00000000"; RETURN dRet; ENDIF //[cite: 3]
      RETURN SToD( cAno + cMes + cDia ) //[cite: 3]
   ELSE
      IF Len( cTemp ) == 8
         IF Val( Left( cTemp, 4 ) ) > 1900
            dRet := SToD( cTemp ) //[cite: 3]
         ELSE
            dRet := SToD( Right( cTemp, 4 ) + SubStr( cTemp, 3, 2 ) + Left( cTemp, 2 ) ) //[cite: 3]
         ENDIF
      ELSEIF Len( cTemp ) == 6
         nAno := Val( Right( cTemp, 2 ) )
         cAno := iif( nAno < 50, "20" + Right( cTemp, 2 ), "19" + Right( cTemp, 2 ) ) //[cite: 3]
         dRet := SToD( cAno + SubStr( cTemp, 3, 2 ) + Left( cTemp, 2 ) ) //[cite: 3]
      ELSE
         dRet := CToD( xData ) //[cite: 3]
      ENDIF
   ENDIF
RETURN dRet