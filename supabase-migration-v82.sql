-- Migration v82: Bulk-assign diver_group for all active divers
-- Generated from diver_group_assignments.xlsx (2026-11-04)
-- 94 divers assigned; 2 duplicates (Jordan Leastman, Julia Prabhu) excluded — resolve manually

-- Canandaigua LTD (5 divers)
UPDATE profiles SET diver_group = 'Canandaigua LTD'
WHERE id IN ('952fe0fc-9eb8-42ee-a1b1-cb7a97f96cf4','c59f6131-49e1-4044-9193-edc7bb7c874e','ff8c1e76-5de1-4568-ba53-02ba3104edd7','744483b5-aa53-4637-bf74-a7e5d5da4bce','f0a0981b-45f3-45fc-9600-856818243795');

-- Canandaigua Lessons (8 divers)
UPDATE profiles SET diver_group = 'Canandaigua Lessons'
WHERE id IN ('e82f9834-4844-42cc-960e-32010f07db15','99538f8a-bcfd-40dc-8412-c0678dfe699f','88f084c0-252b-4dcc-bbf0-54aae655775b','a7bbe2e5-535d-48c8-b354-f5ed382db206','de7bb601-4c9b-45b9-9037-f20657e4da34','01d944e6-adb0-4944-84d7-72cfe22ff3c0','ad5208f8-d99e-40d3-99b7-67c490b8233c','b303d926-7fcb-4958-aa83-268e14e14bb9');

-- Fire (5 divers)
UPDATE profiles SET diver_group = 'Fire'
WHERE id IN ('30311f3f-e80e-4d35-ac53-e78b966b7eec','53b6694b-7085-4b6e-ba25-e3c7a2dbb7cd','8504b8c5-a2eb-400b-bcb0-4bc588485350','39e19a1d-0f87-4f4b-af3c-bfb3957b1ac6','b7c66f66-b811-40d5-a92b-a1c224b2ee65');

-- Learn to Dive (29 divers)
UPDATE profiles SET diver_group = 'Learn to Dive'
WHERE id IN ('b9c835aa-ae6f-4aa7-af8a-215096667c7c','97033254-b531-4e10-b49b-cb068397d8d6','de0d7a5e-7cb5-452e-8344-0da28ae9fcc8','8581df68-9501-4469-8c34-5f62c448a095','e52a533c-59b6-469f-b964-20521282ac2f','0141ac35-11a4-4725-ad06-9526188262ae','1ae2e93e-84c7-43e9-93a6-56d1c4c40b13','e1dc614d-6940-4b08-a515-8c4cb15710c7','7a389050-90d2-4b57-bb0b-6528cab5940c','58881cbc-4781-4a6c-b320-51604997451a','a80105de-19ad-4b94-8bbd-eb90fae7d7c4','324555e7-c0d5-4b87-9146-e588c83927d3','44dde09b-471e-499a-ab7c-817a3c9dd056','825718f6-8636-4170-b01c-fc65dc3729c5','2f345e67-67c8-478d-a99e-bacd2909beba','1f8f38a4-6fe4-420f-bf3e-3a713401e020','ebbc53e4-cd83-42c2-9fc9-04dfa3d56375','23231a07-f349-42c4-bfe3-86852f30fb7e','e5ca6910-7ccf-4a41-98e2-b9b79dc29a9e','83140d65-1b28-4cf6-bcb1-efb862a1ec7f','69e979f2-e3ca-4a77-bddd-cfd31c6b2ae4','2ccccc0f-1491-4a35-9926-28c6e27380a4','fcb32478-b370-43b4-bf25-8ab46280eac9','b3418568-1fb3-43f8-99ac-837657bfbbaa','7a7bb7aa-0409-4c72-ac10-faa052d26275','bcdf6028-2830-4b54-921b-9308141c0458','62556ea8-16c4-4c61-a42e-476be8dae277','389d1f6e-f405-43d6-9002-7f47a938d515','c8eb3a06-6e09-405a-a857-1c55b7d2993e');

-- Lessons (22 divers)
UPDATE profiles SET diver_group = 'Lessons'
WHERE id IN ('62705043-4725-4786-9828-3aacca09a675','4cd2ea0e-eff5-4fa2-97ad-d5d2e3c55102','34f6d9a7-c385-42be-8d5a-792c40fdd4d3','3cdcc032-626b-451a-b269-a5e4770ac85e','f63a6538-1ae2-429d-b4b2-ca4de301c48f','f0407097-fab0-44b3-b969-b2e2544b2df9','67266975-bd85-4b82-8ed1-749f358fdc3c','4fccf8f2-b572-4b3f-b17b-cc5ff811c65c','5fe97d7d-791f-4bb7-8118-55e0d348ad8d','6a48cd08-1265-438f-a1ac-fb37edf99ac8','09b8f982-684e-4965-854c-daa813011913','a52a9e56-2586-4c3b-9f04-e0b1fc390ba0','5b9528fc-ce41-4fdb-bf90-d129ed72d1c2','1a6a93ab-5c7a-4f44-afeb-a816ffd4861d','bbd8d9d4-2e48-440c-9454-1c246539a968','aa05fde0-5cfd-4436-96ff-356eb7c47f23','2d1f0108-4083-47f9-8e5d-dd1be3d09b96','211c0179-3512-4d15-a937-df39b956908f','d8abbefd-c249-48d5-a4b3-ce84b69f403c','7c3d776d-9c7e-4b68-b32f-6e5f2066461a','69da22e5-0183-4f5d-8175-da94cf70fe7a','410eb907-8dec-4445-a955-401e32a5d274');

-- Novice (18 divers)
UPDATE profiles SET diver_group = 'Novice'
WHERE id IN ('e0582b17-b9c5-4af0-80b5-513b07ef1c5f','c211b31d-c4f3-41e9-9c78-f2d8bbf63054','cbd8a07b-d98f-4f83-91c7-eed10ecf44b8','af637bea-1453-4a40-b2ae-372bcbcfbfb0','702407c6-5d1f-4833-8f69-ee4cf824b6f2','a6573a0e-35e4-477a-96a7-311000a42f3e','730c4119-09db-41b5-9148-b2aeb0c31173','62b04941-7c0a-4d6f-b851-82d73170699a','d65b2cd2-df38-4801-85cc-0cf9c84b2d25','8bbce2e0-b39d-42ec-996a-e461e5efa8c8','50b8988c-6a78-41b9-acee-845bdb9c243f','7265adba-f696-4e55-a87c-223e37182e64','ddd0329e-c376-4024-8d63-c0a5e431f12b','4f3d9aa4-3a6e-45de-a695-5ec11a799721','49055622-c484-488e-878b-e11382a7f610','1416b66d-383e-442a-b446-3b8545e3ac17','a8684724-8e1e-4297-9e65-62452643210a','dbcf4e0e-922f-4f51-b8af-59e0644cf846');

-- Sparks (7 divers)
UPDATE profiles SET diver_group = 'Sparks'
WHERE id IN ('81ec6f87-d783-4e2b-8bac-22f6dc16f16d','6a5c7512-e459-4ae1-b341-52fdb5078f8f','17bb8615-158f-4aef-855a-521a3c8780a5','ce965140-bc02-466f-b9b4-10fe6edf661e','f157976c-1cac-4bc4-af04-25725d755e9a','e478679c-2870-439d-9c4c-f35abd5f8673','4d0313ab-a0a0-4888-b6fa-a82a771f99e9');

