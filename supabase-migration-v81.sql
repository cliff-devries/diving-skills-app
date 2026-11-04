-- v81: Reassign Pre-Team diver to Sparks; normalize group name casing

UPDATE profiles
SET diver_group = 'Sparks'
WHERE role = 'diver'
  AND diver_group = 'Pre-Team';
