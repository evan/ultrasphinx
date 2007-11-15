
/* 
 mysqlcompat-1.0b3
 public domain
 modified
 UNIX_TIMESTAMP(date)
*/

CREATE OR REPLACE FUNCTION unix_timestamp(date)
RETURNS bigint AS $$
  SELECT EXTRACT(EPOCH FROM $1)::bigint
$$ VOLATILE LANGUAGE SQL;
