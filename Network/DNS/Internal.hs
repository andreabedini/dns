{-# LANGUAGE DeriveDataTypeable #-}

module Network.DNS.Internal where

import Control.Exception (Exception)
import Data.Bits ((.&.), shiftR, testBit)
import Data.ByteString (ByteString)
import qualified Data.ByteString.Base64 as B64 (encode)
import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.Builder as L
import qualified Data.ByteString.Lazy as L
import Data.IP (IP, IPv4, IPv6)
import Data.Maybe (fromMaybe)
import Data.Typeable (Typeable)
import Data.Word (Word8, Word16, Word32)

----------------------------------------------------------------

-- | Type for domain.
type Domain = ByteString

-- | Return type of composeQuery from Encode, needed in Resolver
type Query = ByteString

----------------------------------------------------------------

-- | Types for resource records.
data TYPE = A
          | AAAA
          | ANY
          | NS
          | TXT
          | MX
          | CNAME
          | SOA
          | PTR
          | SRV
          | DNAME
          | OPT
          | DS
          | RRSIG
          | NSEC
          | DNSKEY
          | NSEC3
          | NSEC3PARAM
          | TLSA
          | CDS
          | CDNSKEY
          | CSYNC
          | NULL
          | UNKNOWN Word16
          deriving (Eq, Show, Read)

-- https://www.iana.org/assignments/dns-parameters/dns-parameters.xhtml#dns-parameters-4
--
rrDB :: [(TYPE, Word16)]
rrDB = [
    (A,      1)
  , (NS,     2)
  , (CNAME,  5)
  , (SOA,    6)
  , (NULL,  10)
  , (PTR,   12)
  , (MX,    15)
  , (TXT,   16)
  , (AAAA,  28)
  , (SRV,   33)
  , (DNAME, 39) -- RFC 6672
  , (OPT,   41) -- RFC 6891
  , (DS,    43) -- RFC 4034
  , (RRSIG, 46) -- RFC 4034
  , (NSEC,  47) -- RFC 4034
  , (DNSKEY, 48) -- RFC 4034
  , (NSEC3, 40) -- RFC 5155
  , (NSEC3PARAM, 51) -- RFC 5155
  , (TLSA,  52) -- RFC 6698
  , (CDS,   59) -- RFC 7344
  , (CDNSKEY, 60) -- RFC 7344
  , (CSYNC, 62) -- RFC 7477
  , (ANY, 255)
  ]

data OPTTYPE = ClientSubnet
             | OUNKNOWN Int
    deriving (Eq)

orDB :: [(OPTTYPE, Int)]
orDB = [
        (ClientSubnet, 8)
       ]

rookup                  :: (Eq b) => b -> [(a,b)] -> Maybe a
rookup _    []          =  Nothing
rookup  key ((x,y):xys)
  | key == y          =  Just x
  | otherwise         =  rookup key xys

intToType :: Word16 -> TYPE
intToType n = fromMaybe (UNKNOWN n) $ rookup n rrDB
typeToInt :: TYPE -> Word16
typeToInt (UNKNOWN x)  = x
typeToInt t = fromMaybe (error "typeToInt") $ lookup t rrDB

intToOptType :: Int -> OPTTYPE
intToOptType n = fromMaybe (OUNKNOWN n) $ rookup n orDB
optTypeToInt :: OPTTYPE -> Int
optTypeToInt (OUNKNOWN x)  = x
optTypeToInt t = fromMaybe (error "optTypeToInt") $ lookup t orDB

----------------------------------------------------------------

-- | An enumeration of all possible DNS errors that can occur.
data DNSError =
    -- | The sequence number of the answer doesn't match our query. This
    --   could indicate foul play.
    SequenceNumberMismatch
    -- | The number of retries for the request was exceeded.
  | RetryLimitExceeded
    -- | The request simply timed out.
  | TimeoutExpired
    -- | The answer has the correct sequence number, but returned an
    --   unexpected RDATA format.
  | UnexpectedRDATA
    -- | The domain for query is illegal.
  | IllegalDomain
    -- | The name server was unable to interpret the query.
  | FormatError
    -- | The name server was unable to process this query due to a
    --   problem with the name server.
  | ServerFailure
    -- | This code signifies that the domain name referenced in the
    --   query does not exist.
  | NameError
    -- | The name server does not support the requested kind of query.
  | NotImplemented
    -- | The name server refuses to perform the specified operation for
    --   policy reasons.  For example, a name
    --   server may not wish to provide the
    --   information to the particular requester,
    --   or a name server may not wish to perform
    --   a particular operation (e.g., zone transfer) for particular data.
  | OperationRefused
    -- | The server detected a malformed OPT RR.
  | BadOptRecord
    -- | Configuration is wrong.
  | BadConfiguration
  deriving (Eq, Show, Typeable)

instance Exception DNSError

-- | Raw data format for DNS Query and Response.
data DNSMessage = DNSMessage {
    header     :: DNSHeader
  , question   :: [Question]
  , answer     :: [ResourceRecord]
  , authority  :: [ResourceRecord]
  , additional :: [ResourceRecord]
  } deriving (Eq, Show)

-- | For backward compatibility.
type DNSFormat = DNSMessage

-- | Raw data format for the header of DNS Query and Response.
data DNSHeader = DNSHeader {
    identifier :: Word16
  , flags      :: DNSFlags
  } deriving (Eq, Show)

-- | Raw data format for the flags of DNS Query and Response.
data DNSFlags = DNSFlags {
    qOrR         :: QorR
  , opcode       :: OPCODE
  , authAnswer   :: Bool
  , trunCation   :: Bool
  , recDesired   :: Bool
  , recAvailable :: Bool
  , rcode        :: RCODE
  , authenData   :: Bool
  } deriving (Eq, Show)

----------------------------------------------------------------

data QorR = QR_Query | QR_Response deriving (Eq, Show, Enum, Bounded)

data OPCODE
  = OP_STD
  | OP_INV
  | OP_SSR
  deriving (Eq, Show, Enum, Bounded)

data RCODE
  = NoErr
  | FormatErr
  | ServFail
  | NameErr
  | NotImpl
  | Refused
  | BadOpt
  deriving (Eq, Ord, Show, Enum, Bounded)

----------------------------------------------------------------

-- | Raw data format for DNS questions.
data Question = Question {
    qname  :: Domain
  , qtype  :: TYPE
  } deriving (Eq, Show)

-- | Making "Question".
makeQuestion :: Domain -> TYPE -> Question
makeQuestion = Question

----------------------------------------------------------------

-- Class. Not used.
type CLASS = Word16

classIN :: CLASS
classIN = 1

-- Time to live.
type TTL = Word32

-- | Raw data format for resource records.
data ResourceRecord = ResourceRecord {
    rrname  :: Domain
  , rrtype  :: TYPE
  , rrclass :: CLASS
  , rrttl   :: TTL
  , rdata   :: RData
  } deriving (Eq,Show)

-- | Raw data format for each type.
data RData = RD_NS Domain
           | RD_CNAME Domain
           | RD_DNAME Domain
           | RD_MX Word16 Domain
           | RD_PTR Domain
           | RD_SOA Domain Domain Word32 Word32 Word32 Word32 Word32
           | RD_A IPv4
           | RD_AAAA IPv6
           | RD_TXT ByteString
           | RD_SRV Word16 Word16 Word16 Domain
           | RD_OPT [OData]
           | RD_OTH ByteString
           | RD_TLSA Word8 Word8 Word8 ByteString
           | RD_DS Word16 Word8 Word8 ByteString
           | RD_NULL  -- anything can be in a NULL record,
                      -- for now we just drop this data.
           | RD_DNSKEY Word16 Word8 Word8 ByteString
    deriving (Eq, Ord)

data OData = OD_ClientSubnet Word8 Word8 IP
           | OD_Unknown Int ByteString
    deriving (Eq,Show,Ord)

-- For OPT pseudo-RR defined in RFC 6891

orUdpSize :: ResourceRecord -> Word16
orUdpSize rr
  | rrtype rr == OPT = rrclass rr
  | otherwise        = error "Can be used only for OPT"

orExtRcode :: ResourceRecord -> Word8
orExtRcode rr
  | rrtype rr == OPT = fromIntegral $ shiftR (rrttl rr .&. 0xff000000) 24
  | otherwise        = error "Can be used only for OPT"

orVersion :: ResourceRecord -> Word8
orVersion rr
  | rrtype rr == OPT = fromIntegral $ shiftR (rrttl rr .&. 0x00ff0000) 16
  | otherwise        = error "Can be used only for OPT"

orDnssecOk :: ResourceRecord -> Bool
orDnssecOk rr
  | rrtype rr == OPT = rrttl rr `testBit` 15
  | otherwise        = error "Can be used only for OPT"

orRdata :: ResourceRecord -> RData
orRdata rr
  | rrtype rr == OPT = rdata rr
  | otherwise        = error "Can be used only for OPT"

instance Show RData where
  show (RD_NS dom) = BS.unpack dom
  show (RD_MX prf dom) = show prf ++ " " ++ BS.unpack dom
  show (RD_CNAME dom) = BS.unpack dom
  show (RD_DNAME dom) = BS.unpack dom
  show (RD_A a) = show a
  show (RD_AAAA aaaa) = show aaaa
  show (RD_TXT txt) = BS.unpack txt
  show (RD_SOA mn _ _ _ _ _ mi) = BS.unpack mn ++ " " ++ show mi
  show (RD_PTR dom) = BS.unpack dom
  show (RD_SRV pri wei prt dom) = show pri ++ " " ++ show wei ++ " " ++ show prt ++ BS.unpack dom
  show (RD_OPT od) = show od
  show (RD_OTH is) = show is
  show (RD_TLSA use sel mtype dgst) = show use ++ " " ++ show sel ++ " " ++ show mtype ++ " " ++ hexencode dgst
  show (RD_DS t a dt dv) = show t ++ " " ++ show a ++ " " ++ show dt ++ " " ++ hexencode dv
  show RD_NULL = "NULL"
  show (RD_DNSKEY f p a k) = show f ++ " " ++ show p ++ " " ++ show a ++ " " ++ b64encode k

hexencode :: ByteString -> String
hexencode = BS.unpack . L.toStrict . L.toLazyByteString . L.byteStringHex

b64encode :: ByteString -> String
b64encode = BS.unpack . B64.encode

----------------------------------------------------------------

defaultQuery :: DNSMessage
defaultQuery = DNSMessage {
    header = DNSHeader {
       identifier = 0
     , flags = DNSFlags {
           qOrR         = QR_Query
         , opcode       = OP_STD
         , authAnswer   = False
         , trunCation   = False
         , recDesired   = True
         , recAvailable = False
         , rcode        = NoErr
         , authenData   = False
         }
     }
  , question   = []
  , answer     = []
  , authority  = []
  , additional = []
  }

defaultResponse :: DNSMessage
defaultResponse =
  let hd = header defaultQuery
      flg = flags hd
  in  defaultQuery {
        header = hd {
          flags = flg {
              qOrR = QR_Response
            , authAnswer = True
            , recAvailable = True
            , authenData = False
            }
        }
      }

responseA :: Word16 -> Question -> [IPv4] -> DNSMessage
responseA ident q ips =
  let hd = header defaultResponse
      dom = qname q
      an = fmap (ResourceRecord dom A classIN 300 . RD_A) ips
  in  defaultResponse {
          header = hd { identifier=ident }
        , question = [q]
        , answer = an
      }

responseAAAA :: Word16 -> Question -> [IPv6] -> DNSMessage
responseAAAA ident q ips =
  let hd = header defaultResponse
      dom = qname q
      an = fmap (ResourceRecord dom AAAA classIN 300 . RD_AAAA) ips
  in  defaultResponse {
          header = hd { identifier=ident }
        , question = [q]
        , answer = an
      }
