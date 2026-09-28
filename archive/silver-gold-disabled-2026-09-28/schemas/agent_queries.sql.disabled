-- Run in the azalea-nezu-gold Athena workgroup with the gold-reader role.
-- IDs here are synthetic. The caller must authorize a real patient's scope.
SELECT * FROM azalea_nezu_gold.medical_events_gold
WHERE patient_id = 'demo-lakshya-001'
ORDER BY occurred_at DESC LIMIT 50;

SELECT * FROM azalea_nezu_gold.prescription_events_gold
WHERE patient_id = 'demo-lakshya-001'
ORDER BY occurred_at DESC LIMIT 50;

SELECT * FROM azalea_nezu_gold.patient_overview
WHERE patient_id = 'demo-lakshya-001';

SELECT * FROM azalea_nezu_gold.patient_timeline
WHERE patient_id = 'demo-lakshya-001'
ORDER BY occurred_at DESC LIMIT 50;

SELECT * FROM azalea_nezu_gold.trace_summaries
WHERE patient_id = 'demo-lakshya-001'
ORDER BY first_started_at DESC LIMIT 20;
