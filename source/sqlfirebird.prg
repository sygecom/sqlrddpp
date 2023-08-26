/* $CATEGORY$SQLRDD/Firebird$FILES$sql.lib$HIDE$
* SQLRDD Firebird Connection Class
* Copyright (c) 2003 - Marcelo Lombardo  <lombardo@uol.com.br>
* All Rights Reserved
*/

/*
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this software; see the file COPYING.  If not, write to
 * the Free Software Foundation, Inc., 59 Temple Place, Suite 330,
 * Boston, MA 02111-1307 USA (or visit the web site http://www.gnu.org/).
 *
 * As a special exception, the xHarbour Project gives permission for
 * additional uses of the text contained in its release of xHarbour.
 *
 * The exception is that, if you link the xHarbour libraries with other
 * files to produce an executable, this does not by itself cause the
 * resulting executable to be covered by the GNU General Public License.
 * Your use of that executable is in no way restricted on account of
 * linking the xHarbour library code into it.
 *
 * This exception does not however invalidate any other reasons why
 * the executable file might be covered by the GNU General Public License.
 *
 * This exception applies only to the code released by the xHarbour
 * Project under the name xHarbour.  If you copy code from other
 * xHarbour Project or Free Software Foundation releases into a copy of
 * xHarbour, as the General Public License permits, the exception does
 * not apply to the code that you add in this way.  To avoid misleading
 * anyone as to the status of such modified files, you must delete
 * this exception notice from them.
 *
 * If you write modifications of your own for xHarbour, it is your choice
 * whether to permit this exception to apply to your modifications.
 * If you do not wish that, delete this exception notice.
 *
 */

#include "hbclass.ch"
#include "common.ch"
#include "compat.ch"
#include "sqlodbc.ch"
#include "sqlrdd.ch"
#include "error.ch"
#include "msg.ch"
#include "firebird.ch"
#include "sqlrddsetup.ch"

#define DEBUGSESSION     .F.
#define ARRAY_BLOCK      500

/*------------------------------------------------------------------------*/

CLASS SR_FIREBIRD FROM SR_CONNECTION

   Data aCurrLine

   METHOD ConnectRaw(cDSN, cUser, cPassword, nVersion, cOwner, nSizeMaxBuff, lTrace, cConnect, nPrefetch, cTargetDB, nSelMeth, nEmptyMode, nDateMode, lCounter, lAutoCommit)
   METHOD End()
   METHOD LastError()
   METHOD Commit()
   METHOD RollBack()
   METHOD IniFields(lReSelect, cTable, cCommand, lLoadCache, cWhere, cRecnoName, cDeletedName)
   METHOD ExecuteRaw(cCommand)
   METHOD AllocStatement()
   METHOD FetchRaw(lTranslate, aFields)
   METHOD FieldGet(nField, aFields, lTranslate)
   METHOD Getline(aFields, lTranslate, aArray)

ENDCLASS

/*------------------------------------------------------------------------*/

METHOD Getline(aFields, lTranslate, aArray) CLASS SR_FIREBIRD

   LOCAL i

   DEFAULT lTranslate TO .T.

   If aArray == NIL
      aArray := Array(len(aFields))
   ElseIf len(aArray) != len(aFields)
      aSize(aArray, len(aFields))
   EndIf

   If ::aCurrLine == NIL
      FBLINEPROCESSED(::hEnv, 4096, aFields, ::lQueryOnly, ::nSystemID, lTranslate, aArray)
      ::aCurrLine := aArray
      RETURN aArray
   EndIf

   For i = 1 to len(aArray)
      aArray[i] := ::aCurrLine[i]
   Next

RETURN aArray

/*------------------------------------------------------------------------*/

METHOD FieldGet(nField, aFields, lTranslate) CLASS SR_FIREBIRD

   If ::aCurrLine == NIL
      DEFAULT lTranslate TO .T.
      ::aCurrLine := array(LEN(aFields))
      FBLINEPROCESSED(::hEnv, 4096, aFields, ::lQueryOnly, ::nSystemID, lTranslate, ::aCurrLine)
   EndIf

RETURN ::aCurrLine[nField]

/*------------------------------------------------------------------------*/

METHOD FetchRaw(lTranslate, aFields) CLASS SR_FIREBIRD

   ::nRetCode := SQL_ERROR
   DEFAULT aFields    TO ::aFields
   DEFAULT lTranslate TO .T.

   If ::hEnv != NIL
      ::nRetCode := FBFetch(::hEnv)
      ::aCurrLine := NIL
   Else
      ::RunTimeErr("", "FBFetch - Invalid cursor state" + chr(13)+chr(10)+ chr(13)+chr(10)+"Last command sent to database : " + chr(13)+chr(10) + ::cLastComm )
   EndIf

RETURN ::nRetCode

/*------------------------------------------------------------------------*/

METHOD AllocStatement() CLASS SR_FIREBIRD

   If ::lSetNext
      If ::nSetOpt == SQL_ATTR_QUERY_TIMEOUT
         // To do.
      EndIf
      ::lSetNext  := .F.
   EndIf

RETURN SQL_SUCCESS

/*------------------------------------------------------------------------*/

METHOD IniFields(lReSelect, cTable, cCommand, lLoadCache, cWhere, cRecnoName, cDeletedName) CLASS SR_FIREBIRD

   LOCAL n
   LOCAL nFields := 0
   LOCAL nType := 0
   LOCAL nLen := 0
   LOCAL nNull := 0
   LOCAL cName
   LOCAL _nLen
   LOCAL _nDec
   LOCAL nPos
   LOCAL cType
   LOCAL nLenField
   LOCAL aFields := {}
   LOCAL nDec := 0
   LOCAL nRet
   LOCAL cVlr := ""
   LOCAL aLocalPrecision := {}

   DEFAULT lReSelect    TO .T.
   DEFAULT lLoadCache   TO .F.
   DEFAULT cWhere       TO ""
   DEFAULT cRecnoName   TO SR_RecnoName()
   DEFAULT cDeletedName TO SR_DeletedName()

   If lReSelect
      If !Empty(cCommand)
         nRet := ::Execute(cCommand + iif(::lComments," /* Open Workarea with custom SQL command */",""), .F.)
      Else
         // DOON'T remove "+0"
         ::Exec([select a.rdb$field_name, b.rdb$field_precision + 0 from rdb$relation_fields a, rdb$fields b where a.rdb$relation_name = '] + StrTran(cTable, ["], []) + [' and a.rdb$field_source = b.rdb$field_name] , .F., .T., @aLocalPrecision)
         nRet := ::Execute("SELECT A.* FROM " + cTable + " A " + iif(lLoadCache, cWhere + " ORDER BY A." + cRecnoName, " WHERE 1 = 0") + iif(::lComments," /* Open Workarea */",""), .F.)
      EndIf
      If nRet != SQL_SUCCESS .AND. nRet != SQL_SUCCESS_WITH_INFO
         RETURN NIL
      EndIf
   EndIf

   if ( ::nRetCode := FBNumResultCols(::hEnv, @nFields) ) != SQL_SUCCESS
      ::RunTimeErr("", "FBNumResultCols Error" + chr(13)+chr(10)+ chr(13)+chr(10)+;
               "Last command sent to database : " + chr(13)+chr(10) + ::cLastComm )
      RETURN NIL
   endif

   aFields   := Array(nFields)
   ::nFields := nFields

   for n = 1 to nFields

      nDec := 0

      if ( ::nRetCode := FBDescribeCol(::hEnv, n, @cName, @nType, @nLen, @nDec, @nNull) ) != SQL_SUCCESS
         ::RunTimeErr("", "FBDescribeCol Error" + chr(13)+chr(10)+ ::LastError() + chr(13)+chr(10)+;
                          "Last command sent to database : " + ::cLastComm )
         RETURN NIL
      else
         _nLen := nLen
         _nDec := nDec

         cName     := upper(alltrim(cName))
         nPos := aScan(aLocalPrecision, { |x| rtrim(x[1]) == cName })
         cType     := ::SQLType(nType, cName, nLen)
         nLenField := ::SQLLen(nType, nLen, @nDec)
         If nPos > 0 .AND. aLocalPrecision[nPos,2] > 0
            nLenField := aLocalPrecision[nPos,2]
         ElseIf ( nType == SQL_DOUBLE .OR. nType == SQL_FLOAT .OR. nType == SQL_NUMERIC )
            nLenField := 19
         EndIf

         If cType == "U"
            ::RuntimeErr("", SR_Msg(21) + cName + " : " + str(nType))
         Else
            aFields[n] := { cName, cType, nLenField, nDec, nNull >= 1 , nType,, n, _nDec,, }
         EndIf

      endif
   next

   ::aFields := aFields

   If lReSelect .AND. !lLoadCache
      ::FreeStatement()
   EndIf

RETURN aFields

/*------------------------------------------------------------------------*/

METHOD LastError() CLASS SR_FIREBIRD

   LOCAL cMsgError
   LOCAL nType := 0

   cMsgError := FBError(::hEnv, @nType)

RETURN alltrim(cMsgError) + " - Native error code " + AllTrim(str(nType))

/*------------------------------------------------------------------------*/

METHOD ConnectRaw(cDSN, cUser, cPassword, nVersion, cOwner, nSizeMaxBuff, lTrace, ;
            cConnect, nPrefetch, cTargetDB, nSelMeth, nEmptyMode, nDateMode, lCounter, lAutoCommit) CLASS SR_FIREBIRD

   LOCAL nRet
   LOCAL hEnv
   LOCAL cSystemVers
   
   HB_SYMBOL_UNUSED(cDSN)
   HB_SYMBOL_UNUSED(cUser)
   HB_SYMBOL_UNUSED(cPassword)
   HB_SYMBOL_UNUSED(nVersion)
   HB_SYMBOL_UNUSED(cOwner)
   HB_SYMBOL_UNUSED(nSizeMaxBuff)
   HB_SYMBOL_UNUSED(lTrace)
   HB_SYMBOL_UNUSED(nPrefetch)
   HB_SYMBOL_UNUSED(nSelMeth)
   HB_SYMBOL_UNUSED(nEmptyMode)
   HB_SYMBOL_UNUSED(nDateMode)
   HB_SYMBOL_UNUSED(lCounter)
   HB_SYMBOL_UNUSED(lAutoCommit)

   nRet := FBConnect(::cDtb, ::cUser, ::cPassword, ::cCharSet, @hEnv)

   if nRet != SQL_SUCCESS
      ::nRetCode = nRet
      SR_MsgLogFile("Connection Error: " + alltrim(str(nRet)) + " (check fb.log) - Database: " + ::cDtb + " - Username : " + ::cUser + " (Password not shown for security)")
      RETURN Self
   else
      ::cConnect  := cConnect
      cTargetDB   := StrTran(FBVERSION(hEnv), "(access method)", "")
      cSystemVers := SubStr(cTargetDB, at("Firebird ", cTargetDB) + 9, 3)
   EndIf

   nRet := FBBeginTransaction(hEnv)

   if nRet != SQL_SUCCESS
      ::nRetCode = nRet
      SR_MsgLogFile("Transaction Start error : " + alltrim(str(nRet)))
      RETURN Self
   EndIf

   ::hEnv         := hEnv
   ::cSystemName  := cTargetDB
   ::cSystemVers  := cSystemVers

   ::DetectTargetDb()

RETURN Self

/*------------------------------------------------------------------------*/

METHOD End() CLASS SR_FIREBIRD

   ::Commit()
   FBClose(::hEnv)

RETURN ::Super:End()

/*------------------------------------------------------------------------*/

METHOD Commit() CLASS SR_FIREBIRD
   ::Super:Commit()
   ::nRetCode := FBCOMMITTRANSACTION(::hEnv )  
RETURN ( ::nRetCode := FBBeginTransaction(::hEnv) )

/*------------------------------------------------------------------------*/

METHOD RollBack() CLASS SR_FIREBIRD
   ::Super:RollBack()
RETURN ( ::nRetCode := FBRollBackTransaction(::hEnv) )

/*------------------------------------------------------------------------*/

METHOD ExecuteRaw(cCommand) CLASS SR_FIREBIRD

   LOCAL nRet

   If upper(left(ltrim(cCommand), 6)) == "SELECT"
      nRet := FBExecute(::hEnv, cCommand, IB_DIALECT_CURRENT)
      ::lResultSet := .T.
   Else
      nRet := FBExecuteImmediate(::hEnv, cCommand, IB_DIALECT_CURRENT)
      ::lResultSet := .F.
   EndIf

RETURN nRet

/*------------------------------------------------------------------------*/
