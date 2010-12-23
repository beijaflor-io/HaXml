module Text.XML.HaXml.Schema.PrettyHaskell
  ( ppComment
  , ppModule
  , ppHighLevelDecl
  , ppHighLevelDecls
  , ppvList
  ) where

import Text.XML.HaXml.Types (QName(..),Namespace(..))
import Text.XML.HaXml.Schema.HaskellTypeModel
import Text.XML.HaXml.Schema.XSDTypeModel (Occurs(..))
import Text.XML.HaXml.Schema.NameConversion
import Text.PrettyPrint.HughesPJ as PP

import List (intersperse,notElem)

-- | Vertically pretty-print a list of things, with open and close brackets,
--   and separators.
ppvList :: String -> String -> String -> (a->Doc) -> [a] -> Doc
ppvList open sep close pp []     = text open <> text close
ppvList open sep close pp (x:xs) = text open <+> pp x
                                   $$ vcat (map (\y-> text sep <+> pp y) xs)
                                   $$ text close

data CommentPosition = Before | After

-- | Generate aligned haddock-style documentation.
--   (but without escapes in comment text yet)
ppComment :: CommentPosition -> Comment -> Doc
ppComment _   Nothing  = empty
ppComment pos (Just s) =
    text "--" <+> text (case pos of Before -> "|"; After -> "^") <+> text c
    $$
    vcat (map (\x-> text "--  " <+> text x) cs)
  where
    (c:cs) = lines (paragraph 60 s)

-- | Pretty-print a Haskell-style name.
ppHName :: HName -> Doc
ppHName (HName x) = text x

-- | Pretty-print an XML-style name.
ppXName :: XName -> Doc
ppXName (XName (N x))     = text x
ppXName (XName (QN ns x)) = text (nsPrefix ns) <> text ":" <> text x

-- | Some different ways of using a Haskell identifier.
ppModId, ppConId, ppVarId, ppUnqConId, ppUnqVarId
    :: NameConverter -> XName -> Doc
ppModId nx = ppHName . modid nx
ppConId nx = ppHName . conid nx
ppVarId nx = ppHName . varid nx
ppUnqConId nx = ppHName . unqconid nx
ppUnqVarId nx = ppHName . unqvarid nx
ppFieldId  nx = \t-> ppHName . fieldid nx t

ppJoinConId :: NameConverter -> XName -> XName -> Doc
ppJoinConId nx p q = ppHName (conid nx p) <> text "_" <> ppHName (conid nx q)

-- | Convert a whole document from HaskellTypeModel to Haskell source text.
ppModule :: NameConverter -> Module -> Doc
ppModule nx m =
    text "{-# LANGUAGE MultiParamTypeClasses, FunctionalDependencies,"
    $$ text "             ExistentialQuantification #-}"
    $$ text "{-# OPTIONS_GHC -fno-warn-duplicate-exports #-}"
    $$ text "module" <+> ppModId nx (module_name m)
    $$ nest 2 (text "( module" <+> ppModId nx (module_name m)
              $$ vcat (map (\(XSDInclude ex com)->
                               ppComment Before com
                               $$ text ", module" <+> ppModId nx ex)
                           (module_re_exports m))
              $$ text ") where")
    $$ text " "
    $$ text "import Text.XML.HaXml.Schema.Schema (SchemaType(..),SimpleType(..),Extension(..),Restricts(..))"
    $$ text "import Text.XML.HaXml.Schema.Schema as Schema"
    $$ (case module_xsd_ns m of
         Nothing -> text "import Text.XML.HaXml.Schema.PrimitiveTypes as Xsd"
         Just ns -> text "import qualified Text.XML.HaXml.Schema.PrimitiveTypes as"<+>ppConId nx ns)
    $$ vcat (map (ppHighLevelDecl nx)
                 (module_re_exports m ++ module_import_only m))
    $$ text " "
    $$ ppHighLevelDecls nx (module_decls m)

-- | Generate a fragmentary parser for an attribute.
ppAttr :: Attribute -> Int -> Doc
ppAttr a n = (text "a"<>text (show n)) <+> text "<- getAttribute \""
                                       <> ppXName (attr_name a)
                                       <> text "\" e pos"
-- | Generate a fragmentary parser for an element.
ppElem :: NameConverter -> Element -> Doc
ppElem nx e@Element{}
    | elem_byRef e    = ppElemModifier (elem_modifier e)
                                       (text "element"
                                        <> ppUnqConId nx (elem_name e))
    | otherwise       = ppElemModifier (elem_modifier e)
                                       (text "parseSchemaType \""
                                        <> ppXName (elem_name e)
                                        <> text "\"")
ppElem nx e@AnyElem{} = ppElemModifier (elem_modifier e)
                          (text "parseAnyElement")
ppElem nx e@Text{}    = text "parseText"
ppElem nx e@OneOf{}   = ppElemModifier (elem_modifier e)
                          (text "oneOf" <+> ppvList "[" "," "]"
                                                    (ppOneOf n)
                                                    (zip (elem_oneOf e) [1..n]))
  where
    n = length (elem_oneOf e)
    ppOneOf n (e,i) = text "fmap" <+> text (ordinal i ++"Of"++show n)
                      <+> parens (ppSeqElem e)
    ordinal i | i <= 20   = ordinals!!i
              | otherwise = "Choice" ++ show i
    ordinals = ["Zero","One","Two","Three","Four","Five","Six","Seven","Eight"
               ,"Nine","Ten","Eleven","Twelve","Thirteen","Fourteen","Fifteen"
               ,"Sixteen","Seventeen","Eighteen","Nineteen","Twenty"]
    ppSeqElem []  = PP.empty
    ppSeqElem [e] = ppElem nx e
    ppSeqElem es  = text ("return ("++replicate (length es-1) ','++")")
                    <+> vcat (map (\e-> text "`apply`" <+> ppElem nx e) es)

-- | Convert multiple HaskellTypeModel Decls to Haskell source text.
ppHighLevelDecls :: NameConverter -> [Decl] -> Doc
ppHighLevelDecls nx hs = vcat (intersperse (text " ")
                                           (map (ppHighLevelDecl nx) hs))

-- | Convert a single Haskell Decl into Haskell source text.
ppHighLevelDecl :: NameConverter -> Decl -> Doc

ppHighLevelDecl nx (NamedSimpleType t s comm) =
    ppComment Before comm
    $$ text "type" <+> ppUnqConId nx t <+> text "=" <+> ppConId nx s
    $$ text "-- No instances required: synonym is isomorphic to the original."

ppHighLevelDecl nx (RestrictSimpleType t s r comm) =
    ppComment Before comm
    $$ text "newtype" <+> ppUnqConId nx t <+> text "="
                      <+> ppUnqConId nx t <+> ppConId nx s
                      <+> text "deriving (Eq,Show)"
    $$ text "instance Restricts" <+> ppUnqConId nx t <+> ppConId nx s
                      <+> text "where"
        $$ nest 4 (text "restricts (" <> ppUnqConId nx t <+> text "x) = x")
    $$ text "instance SchemaType" <+> ppUnqConId nx t <+> text "where"
        $$ nest 4 (text "parseSchemaType s = do" 
                  $$ nest 4 (text "e <- element [s]"
                           $$ text "commit $ interior e $ parseSimpleType")
                  )
    $$ text "instance SimpleType" <+> ppUnqConId nx t <+> text "where"
        $$ nest 4 (text "acceptingParser = fmap" <+> ppUnqConId nx t
                                                 <+> text "acceptingParser"
                   -- XXX should enforce the restrictions somehow.  (?)
                   $$ text "-- XXX should enforce the restrictions somehow?"
                   $$ text "-- The restrictions are:"
                   $$ vcat (map ((text "--     " <+>) . ppRestrict) r))
  where
    ppRestrict (RangeR occ comm)     = text "(RangeR"
                                         <+> ppOccurs occ <>  text ")"
    ppRestrict (Pattern regexp comm) = text ("(Pattern "++regexp++")")
    ppRestrict (Enumeration items)   = text "(Enumeration"
                                         <+> hsep (map (text . fst) items)
                                         <>  text ")"
    ppRestrict (StrLength occ comm)  = text "(StrLength"
                                         <+> ppOccurs occ <>  text ")"
    ppOccurs = parens . text . show

ppHighLevelDecl nx (ExtendSimpleType t s as comm) =
    ppComment Before comm
    $$ text "data" <+> ppUnqConId nx t <+> text "="
                                    <+> ppUnqConId nx t <+> ppConId nx s
                                    <+> ppConId nx t_attrs
    $$ text "data" <+> ppConId nx t_attrs <+> text "=" <+> ppConId nx t_attrs
        $$ nest 4 (ppFields nx t_attrs [] as)
    $$ text "instance SchemaType" <+> ppUnqConId nx t <+> text "where"
        $$ nest 4 (text "parseSchemaType s = do" 
                  $$ nest 4 (text "(pos,e) <- posnElement [s]"
                            $$ text "commit $ do"
                            $$ nest 2
                                  (vcat (zipWith ppAttr as [0..])
                                  $$ text "reparse [CElem e pos]"
                                  $$ text "v <- parseSchemaType s"
                                  $$ text "return $" <+> ppUnqConId nx t
                                                     <+> text "v"
                                                     <+> attrsValue as)
                            )
                  )
    $$ text "instance Extension" <+> ppUnqConId nx t <+> ppConId nx s
                                 <+> text "where"
        $$ nest 4 (text "supertype (" <> ppUnqConId nx t <> text " s _) = s")
  where
    t_attrs = let (XName (N t_base)) = t in XName (N (t_base++"Attributes"))

    attrsValue [] = ppConId nx t_attrs
    attrsValue as = parens (ppConId nx t_attrs <+>
                            hsep [text ("a"++show n) | n <- [0..length as-1]])

    -- do element [s]
    --    blah <- attribute foo
    --    interior e $ do
    --        simple <- parseText acceptingParser
    --        return (T simple blah)

ppHighLevelDecl nx (UnionSimpleTypes t sts comm) =
    ppComment Before comm
    $$ text "data" <+> ppUnqConId nx t <+> text "=" <+> ppUnqConId nx t
    $$ text "-- Placeholder for a Union type, not yet implemented."

ppHighLevelDecl nx (EnumSimpleType t [] comm) =
    ppComment Before comm
    $$ text "data" <+> ppUnqConId nx t
ppHighLevelDecl nx (EnumSimpleType t is comm) =
    ppComment Before comm
    $$ text "data" <+> ppUnqConId nx t
        $$ nest 4 ( ppvList "=" "|" "deriving (Eq,Show,Enum)" item is )
    $$ text "instance SchemaType" <+> ppUnqConId nx t <+> text "where"
        $$ nest 4 (text "parseSchemaType s = do" 
                  $$ nest 4 (text "e <- element [s]"
                           $$ text "commit $ interior e $ parseSimpleType")
                  )
    $$ text "instance SimpleType" <+> ppUnqConId nx t <+> text "where"
        $$ nest 4 (text "acceptingParser ="
                        <+> ppvList "" "`onFail`" "" parseItem is)
  where
    item (i,c) = (ppUnqConId nx t <> text "_" <> ppConId nx i)
                 $$ ppComment After c
    parseItem (i,_) = text "do isWord \"" <> ppXName i <> text "\"; return"
                           <+> (ppUnqConId nx t <> text "_" <> ppConId nx i)

ppHighLevelDecl nx (ElementsAttrs t es as comm) =
    ppComment Before comm
    $$ text "data" <+> ppUnqConId nx t <+> text "=" <+> ppUnqConId nx t
        $$ nest 8 (ppFields nx t (uniqueify es) as)
    $$ text "instance SchemaType" <+> ppUnqConId nx t <+> text "where"
        $$ nest 4 (text "parseSchemaType s = do" 
                  $$ nest 4 (text "(pos,e) <- posnElement [s]"
                            $$ text "commit $ do"
                            $$ nest 2
                                  (vcat (zipWith ppAttr as [0..])
                                  $$ text "interior e $ return"
                                      <+> returnValue as
                                      $$ nest 4 (vcat (map ppApplyElem es))
                                  )
                            )
                  )
  where
    returnValue [] = ppUnqConId nx t
    returnValue as = parens (ppUnqConId nx t <+>
                             hsep [text ("a"++show n) | n <- [0..length as-1]])
    ppApplyElem e = text "`apply`" <+> ppElem nx e

ppHighLevelDecl nx (ElementsAttrsAbstract t insts comm) =
    ppComment Before comm
    $$ text "data" <+> ppUnqConId nx t
        $$ nest 8 (ppvList "=" "|" "" ppAbstrCons insts)
    $$ text "instance SchemaType" <+> ppUnqConId nx t <+> text "where"
        $$ nest 4 (text "parseSchemaType s = do" 
                  $$ nest 4 (vcat (intersperse (text "`onFail`")
                                               (map ppParse insts)
                                   ++ [text "`onFail` fail" <+> errmsg]))
    $$ vcat (map (ppFwdDecl . fst) $ filter snd insts)
  where
    ppAbstrCons (name,False) = con name <+> ppConId nx name
    ppAbstrCons (name,True)  = text "forall q . (FwdDecl" <+>
                               fwd name <+> text "q," <+>
                               text "SchemaType q) =>" <+>
                               con name <+>
                               text "("<>fwd name<>text"->q)" <+> fwd name
    ppParse (name,False) = text "(fmap" <+> con name <+>
                           text "$ parseSchemaType s)"
    ppParse (name,True)  = text "(return" <+> con name <+>
                           text "`apply` (fmap const $ parseSchemaType s)" <+>
                           text "`apply` return" <+> fwd name <> text ")"
    ppFwdDecl name = text "data" <+> fwd name <+> text "=" <+> fwd name
    errmsg = text "\"Parse failed when expecting an extension type of"
             <+> ppXName t <> text ",\n  namely one of:\n"
             <> hcat (intersperse (text ",")
                                  (map (ppXName . fst) insts))
             <> text "\""
    fwd name = text "Fwd" <> ppConId nx name
    con name = ppJoinConId nx t name

--------------------------------------------------------------

ppHighLevelDecl nx (ElementOfType e@Element{}) =
    ppComment Before (elem_comment e)
    $$ (text "element" <> ppUnqConId nx (elem_name e)) <+> text "::"
        <+> text "XMLParser" <+> ppConId nx (elem_type e)
    $$ (text "element" <> ppUnqConId nx (elem_name e)) <+> text "="
        <+> (text "parseSchemaType \"" <> ppXName (elem_name e)  <> text "\"")

ppHighLevelDecl nx (ElementAbstractOfType n t substgrp comm) =
    ppComment Before comm
    $$ (text "element" <> ppUnqConId nx n) <+> text "::"
        <+> text "XMLParser" <+> ppConId nx t
    $$ (text "element" <> ppUnqConId nx n) <+> text "="
       vcat (intersperse (text "`onFail`") (map ppOne substgrp)
             ++ [text "`onFail` fail" <+> errmsg])
  where
    ppOne (c,e) = text "fmap" <+> ppJoinConId nx t c
                  <+> (text "element" <> ppConId e)
    errmsg = text "\"Parse failed when expecting an element in the substitution group for\n  <"
             <> ppXName n <> text ">,\nnamely one of:\n<"
             <> hcat (intersperse (text ">, <")
                                  (map (ppXName . snd) substgrp))
             <> text ">\""

ppHighLevelDecl nx (Choice t es comm) =
    ppComment Before comm
    $$ text "data" <+> ppUnqConId nx t
        <+> nest 4 ( ppvList "=" "|" "" choices (zip es [1..]) )
  where
    choices (e,n) = (ppUnqConId nx t <> text (show n))
                    <+> ppConId nx (elem_type e)

-- Comment out the Group for now.  Groups get inlined into the ComplexType
-- where they are used, so it may not be sensible to declare them separately
-- as well.
ppHighLevelDecl nx (Group t es comm) = PP.empty
--  ppComment Before comm
--  $$ text "data" <+> ppConId nx t <+> text "="
--                 <+> ppConId nx t <+> hsep (map (ppConId nx . elem_type) es)

-- Possibly we want to declare a really more restrictive type, e.g. 
--    to remove optionality, (Maybe Foo) -> (Foo), [Foo] -> Foo
--    consequently the "restricts" method should do a proper translation,
--    not merely an unwrapping.
ppHighLevelDecl nx (RestrictComplexType t s comm) =
    ppComment Before comm
    $$ text "newtype" <+> ppUnqConId nx t <+> text "="
                                       <+> ppUnqConId nx t <+> ppConId nx s
    $$ text "-- plus different (more restrictive) parser"
    $$ text "instance Restricts" <+> ppUnqConId nx t <+> ppConId nx s
                                 <+> text "where"
        $$ nest 4 (text "restricts (" <> ppUnqConId nx t <+> text "x) = x")
    $$ text "instance SchemaType" <+> ppUnqConId nx t <+> text "where"
        $$ nest 4 (text "parseSchemaType = fmap " <+> ppUnqConId nx t <+>
                   text ". parseSchemaType")
		-- XXX should enforce the restriction.

{-
ppHighLevelDecl nx (ExtendComplexType t s es as _ comm)
    | length es + length as = 1 =
    ppComment Before comm
    $$ text "data" <+> ppConId nx t <+> text "="
                                    <+> ppConId nx t <+> ppConId nx s
                                    <+> ppFields nx t es as
    $$ text "instance Extension" <+> ppConId nx t <+> ppConId nx s
                                 <+> ppAuxConId nx t <+> text "where"
        $$ nest 4 (text "supertype (" <> ppConId nx t <> text " s e) = s"
                   $$ text "extension (" <> ppConId nx t <> text " s e) = e")
-}
ppHighLevelDecl nx (ExtendComplexType t s oes oas es as abstr comm) =
    ppHighLevelDecl nx (ElementsAttrs t (oes++es) (oas++as) comm)
    $$ text "instance Extension" <+> ppUnqConId nx t <+> ppUnqConId nx s
                                 <+> text "where"
        $$ nest 4 (text "supertype (" <> ppType t (oes++es) (oas++as)
                                      <> text ") ="
                                      $$ nest 11 (ppType s oes oas) )
  where
    ppType t es as = ppUnqConId nx t
                     <+> hsep (take (length as) [text ('a':show n) | n<-[0..]])
                     <+> hsep (take (length es) [text ('e':show n) | n<-[0..]])

ppHighLevelDecl nx (ExtendComplexTypeAbstract t s insts fwdReqd comm) =
    text "ExtendComplexTypeAbstract not implemented"
--  ppHighLevelDecl nx (ElementsAttrs t (oes++es) (oas++as) comm)
--  $$ text "instance Extension" <+> ppUnqConId nx t <+> ppUnqConId nx s
--                               <+> text "where"
--      $$ nest 4 (text "supertype (" <> ppType t (oes++es) (oas++as)
--                                    <> text ") ="
--                                    $$ nest 11 (ppType s oes oas) )
--where
--  ppType t es as = ppUnqConId nx t
--                   <+> hsep (take (length as) [text ('a':show n) | n<-[0..]])
--                   <+> hsep (take (length es) [text ('e':show n) | n<-[0..]])

ppHighLevelDecl nx (XSDInclude m comm) =
    ppComment After comm
    $$ text "import" <+> ppModId nx m

ppHighLevelDecl nx (XSDImport m ma comm) =
    ppComment After comm
    $$ text "import" <+> ppModId nx m
                     <+> maybe empty (\a->text "as"<+>ppConId nx a) ma

ppHighLevelDecl nx (XSDComment comm) =
    ppComment Before comm


--------------------------------------------------------------------------------

-- | Generate named fields from elements and attributes.
ppFields :: NameConverter -> XName -> [Element] -> [Attribute] -> Doc
ppFields nx t es as | null es && null as = empty
ppFields nx t es as =  ppvList "{" "," "}" id fields
  where
    fields = map (ppFieldAttribute nx t) as ++
             zipWith (ppFieldElement nx t) es [0..]

-- | Generate a single named field from an element.
ppFieldElement :: NameConverter -> XName -> Element -> Int -> Doc
ppFieldElement nx t e@Element{} _ = ppFieldId nx t (elem_name e)
                                        <+> text "::" <+> ppElemTypeName nx id e
                                    $$ ppComment After (elem_comment e)
ppFieldElement nx t e@OneOf{}   i = ppFieldId nx t (XName $ N $"choice"++show i)
                                        <+> text "::" <+> ppElemTypeName nx id e
                                    $$ ppComment After (elem_comment e)
ppFieldElement nx t e@AnyElem{} i = ppFieldId nx t (XName $ N $"any"++show i)
                                        <+> text "::" <+> ppElemTypeName nx id e
                                    $$ ppComment After (elem_comment e)
ppFieldElement nx t e@Text{}    i = ppFieldId nx t (XName $ N $"text"++show i)
                                        <+> text "::" <+> ppElemTypeName nx id e

-- | What is the name of the type for an Element (or choice of Elements)?
ppElemTypeName :: NameConverter -> (Doc->Doc) -> Element -> Doc
ppElemTypeName nx brack e@Element{} =
    ppTypeModifier (elem_modifier e) brack $ ppConId nx (elem_type e)
ppElemTypeName nx brack e@OneOf{}   = 
    brack $ ppTypeModifier (elem_modifier e) parens $
    text "OneOf" <> text (show (length (elem_oneOf e)))
     <+> hsep (map ppSeq (elem_oneOf e))
  where
    ppSeq []  = text "()"
    ppSeq [e] = ppElemTypeName nx parens e
    ppSeq es  = text "(" <> hcat (intersperse (text ",")
                                     (map (ppElemTypeName nx parens) es))
                         <> text ")"
ppElemTypeName nx brack e@AnyElem{} =
    brack $ ppTypeModifier (elem_modifier e) id $
    text "AnyElement"
ppElemTypeName nx brack e@Text{} =
    text "String"

-- | Generate a single named field from an attribute.
ppFieldAttribute :: NameConverter -> XName -> Attribute -> Doc
ppFieldAttribute nx t a = ppFieldId nx t (attr_name a) <+> text "::"
                                   <+> ppConId nx (attr_type a)
                          $$ ppComment After (attr_comment a)

-- | Generate a list or maybe type name (possibly parenthesised).
ppTypeModifier :: Modifier -> (Doc->Doc) -> Doc -> Doc
ppTypeModifier Single   _ d  = d
ppTypeModifier Optional k d  = k $ text "Maybe" <+> k d
ppTypeModifier (Range (Occurs Nothing Nothing))  _ d = d
ppTypeModifier (Range (Occurs (Just 0) Nothing)) k d = k $ text "Maybe" <+> k d
ppTypeModifier (Range (Occurs _ _))              _ d = text "[" <> d <> text "]"

-- | Generate a parser for a list or Maybe value.
ppElemModifier Single    doc = doc
ppElemModifier Optional  doc = text "optional" <+> parens doc
ppElemModifier (Range (Occurs Nothing Nothing))  doc = doc
ppElemModifier (Range (Occurs (Just 0) Nothing)) doc = text "optional"
                                                       <+> parens doc
ppElemModifier (Range o) doc = text "between" <+> (parens (text (show o))
                                                  $$ parens doc)

-- | Split long lines of comment text into a paragraph with a maximum width.
paragraph :: Int -> String -> String
paragraph n s = go n (words s)
    where go i []     = []
          go i (x:xs) | len<i     =       x++" "++go (i-len-1) xs
                      | otherwise = "\n"++x++" "++go (n-len-1) xs
              where len = length x

uniqueify :: [Element] -> [Element]
uniqueify = go []
  where
    go seen [] = []
    go seen (e@Element{}:es)
        | show (elem_name e) `elem` seen
                    = let fresh = new (`elem`seen) (elem_name e) in
                      e{elem_name=fresh} : go (show fresh:seen) es
        | otherwise = e: go (show (elem_name e): seen) es
    go seen (e:es)  = e : go seen es
    new pred (XName (N n))     = XName $ N $ head $
                                 dropWhile pred [(n++show i) | i <- [2..]]
    new pred (XName (QN ns n)) = XName $ QN ns $ head $
                                 dropWhile pred [(n++show i) | i <- [2..]]

