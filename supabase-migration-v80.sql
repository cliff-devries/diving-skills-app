-- v80: Normalize diving_location — collapse all program/group variants to the two real locations

UPDATE crm_leads
SET diving_location = CASE
  -- RIT variants
  WHEN diving_location IN (
    'RIT Pool',
    'RIT Learn to Dive',
    'Learn to Dive',
    'Lessons',
    'RIT Intermediate',
    'Competition Team - Blaze',
    'Sparks',
    'Competition Team - Fire',
    'RIT',
    'Masters - Adult Diving'
  ) THEN 'RIT'

  -- Canandaigua variants
  WHEN diving_location IN (
    'Canandaigua Academy',
    'Canandaigua',
    'Canandaigua Intermediate',
    'Canandaigua Learn to Dive'
  ) THEN 'Canandaigua'

  ELSE diving_location
END
WHERE diving_location NOT IN ('RIT', 'Canandaigua')
  AND diving_location IS NOT NULL;
