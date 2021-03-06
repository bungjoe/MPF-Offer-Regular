CREATE OR REPLACE FORCE VIEW V_CAMP_COMPLAINT AS
SELECT A.DATE_EFFECTIVE, A.CODE_EMPLOYEE_TASK_TYPE,	A.CODE_EMPLOYEE_TASK_SUBTYPE,	
       A.NAME_EMPLOYEE_TASK_ACCESS_ROLE,	A.NAME_EMPLOYEE_TASK_TYPE,	A.NAME_EMPLOYEE_TASK_SUBTYPE, 
       A.CODE_TASK, A.NAME_EMPLOYEE, A.CODE_EMPLOYEE, A.TEXT_CONTRACT_NUMBER, A.ID_CUID, 
       B.NAME_FULL, TO_CHAR(B.DATE_BIRTH, 'DD-Mon-YYYY') DATE_BIRTH, A.TEXT_TASK_NOTE
FROM (
      SELECT *
      FROM (
            SELECT DATE_EFFECTIVE, CODE_EMPLOYEE_TASK_TYPE,	CODE_EMPLOYEE_TASK_SUBTYPE,	NAME_EMPLOYEE_TASK_ACCESS_ROLE,	NAME_EMPLOYEE_TASK_TYPE,	NAME_EMPLOYEE_TASK_SUBTYPE, 
                   CODE_TASK, NAME_EMPLOYEE, CODE_EMPLOYEE, TEXT_CONTRACT_NUMBER, SKP_CLIENT, ID_CUID, TEXT_TASK_NOTE, 
                   ROW_NUMBER() OVER (PARTITION BY CODE_TASK ORDER BY (CASE WHEN DTIME_INSERTED IS NULL THEN DATE_EFFECTIVE ELSE DTIME_INSERTED END) DESC) ROWN
            FROM AP_CRM.CAMP_COMPL_REG
            UNION ALL
            SELECT DATE_EFFECTIVE, CODE_EMPLOYEE_TASK_TYPE,	CODE_EMPLOYEE_TASK_SUBTYPE,	NAME_EMPLOYEE_TASK_ACCESS_ROLE,	NAME_EMPLOYEE_TASK_TYPE,	NAME_EMPLOYEE_TASK_SUBTYPE, 
                   CODE_TASK, NAME_EMPLOYEE, CODE_EMPLOYEE, TEXT_CONTRACT_NUMBER, SKP_CLIENT, ID_CUID, TEXT_TASK_NOTE,
                   ROW_NUMBER() OVER (PARTITION BY CODE_TASK ORDER BY (CASE WHEN DTIME_INSERTED IS NULL THEN DATE_EFFECTIVE ELSE DTIME_INSERTED END) DESC) ROWN
            FROM AP_CRM.CAMP_COMPL_VIP
            )
      WHERE ROWN = 1
      ) A
LEFT JOIN OWNER_DWH.DC_CLIENT B ON A.SKP_CLIENT = B.SKP_CLIENT;

