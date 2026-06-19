# Moves AZ DES and PA DHS partner-specific translations out of config/locales/en.yml
# and es.yml and into the partner_translations table.
#
# Values are embedded verbatim (as JSON) so this migration is self-contained and does
# NOT read the locale files, which are edited in the same change to remove these keys.
# agency_translation/db_translation strip a trailing ".<partner_id>" on lookup, so
# suffix-style keys are stored under their base key (e.g. "shared.agency_acronym");
# the caseworker invitation keys carry the partner id mid-path and are stored verbatim.
class SeedAzDesPaDhsPartnerTranslations < ActiveRecord::Migration[7.2]
  TRANSLATIONS = JSON.parse(<<~'JSON')
    {
      "az_des/en": {
        "caseworker.cbv_flow_invitations.az_des.invite.case_number": "Case number",
        "caseworker.cbv_flow_invitations.az_des.invite.email_address": "Client's email address",
        "caseworker.cbv_flow_invitations.az_des.invite.language_label": "In what language should we send the invitation?",
        "cbv.submits.show.consent_checkbox_label_html": "Check this box to affirm under penalty of perjury that the information provided by you is true and complete to the best of your knowledge.<ul class=\"margin-y-2\"><li>You agree to tell %{agency_acronym} about:<ul><li>any other income not included in this report,</li><li>or any errors found in the information gathered with this tool.</li></ul></li><li>You understand that providing accurate and complete information is your responsibility.</li><li>Any false or missing information may result in:<ul><li>an overpayment, which you must repay to %{agency_acronym},</li><li>or program disqualification.</li></ul></li></ul>By sending this report, you authorize its use for income verification by %{agency_acronym} and authorized personnel.",
        "cbv.submits.show.pdf.agency_header_name": "Department of Economic Security",
        "shared.agency_acronym": "DES/FAA",
        "shared.agency_full_name": "Department of Economic Security/Family Assistance Administration",
        "shared.agency_portal_name": "DES/FAA",
        "shared.app_name": "MyFamilyBenefits",
        "shared.benefit": "Nutrition Assistance",
        "shared.header.cbv_flow_title": "Department of Economic Security",
        "shared.header.preheader": "A website in partnership with the Arizona Department of Economic Security."
      },
      "pa_dhs/en": {
        "cbv.entries.show.checkbox": "I agree that Verify My Income can access my income, including W-2 and/or gig work information. After reviewing my income details, I can choose to share my income with the PA Department of Human Services (DHS). If shared, DHS will use my income details to determine my benefits. I understand that Verify My Income will not have ongoing access to my income details.",
        "cbv.submits.show.consent_checkbox_label_html": "<strong>I agree and confirm:</strong><p><strong>I am sharing accurate information.</strong><br>The information I provided is true and complete to the best of my knowledge. I will not share the report if anything in it is incorrect.<p><strong>I will share any missing information.</strong><br>I agree to inform the PA Department of Human Services about any income that is not in this report.<p><strong>I am not sharing false information.</strong><br>I understand that I must share honest information. I understand I could get in legal trouble if I leave out information.<p><strong>I will share my income information.</strong><br>I allow the income information this webpage showed me to be shared with the PA Department of Human Services.",
        "cbv.submits.show.pdf.agency_header_name": "Department of Human Services",
        "shared.agency_acronym": "DHS",
        "shared.agency_full_name": "Pennsylvania Department of Human Services",
        "shared.agency_portal_name": "COMPASS",
        "shared.app_name": "VerifyMyIncome",
        "shared.benefit": "Nutrition Assistance",
        "shared.header.cbv_flow_title": "Department of Human Services",
        "shared.header.preheader": "A website in partnership with the Pennsylvania Department of Human Services"
      },
      "az_des/es": {
        "cbv.submits.show.consent_checkbox_label_html": "Marque esta casilla para confirmar, bajo pena de perjurio, que la información proporcionada es, a su leal saber y entender, verdadera y está completa.<ul class=\"margin-y-2\"><li>Se compromete a informar %{agency_acronym} de cualquiera de lo siguiente:<ul><li>cualquier otro ingreso que no esté incluido en este informe;</li><li>o cualquier error que haya detectado en la información recopilada con esta herramienta.</li></ul></li><li>Comprende que usted es el único responsable de proporcionar información precisa y completa.</li><li>Por este motivo, cualquier información falsa o que no conste en el informe puede acarrear las siguientes consecuencias:<ul><li>un sobrepago, que debe reembolsar a %{agency_acronym};</li><li>o una inhabilitación para participar en el programa.</li></ul></li></ul>Al enviar este informe, autoriza su uso para fines de verificación de ingresos por parte de %{agency_acronym} y del personal autorizado de esta agencia.",
        "cbv.submits.show.pdf.agency_header_name": "Department of Economic Security",
        "shared.agency_acronym": "DES/FAA",
        "shared.agency_full_name": "Departamento de Seguridad Económica de Arizona/Administración de Asistencia Familiar",
        "shared.agency_portal_name": "DES/FAA",
        "shared.app_name": "MyFamilyBenefits",
        "shared.benefit": "Asistencia Nutricional",
        "shared.header.cbv_flow_title": "Departamento de Seguridad Económica",
        "shared.header.preheader": "Un sitio web en colaboración con el Departamento de Seguridad Económica de Arizona."
      },
      "pa_dhs/es": {
        "cbv.entries.show.checkbox": "Acepto que Verificar Mis Ingresos acceda a mis ingresos, incluido el W-2 y/o información sobre trabajos temporales. Después de revisar la información de mis ingresos, puedo elegir compartir mis ingresos con el Departamento de Servicios Humanos (DHS) de PA. Si la comparto, el DHS utilizará la información de mis ingresos para determinar mis beneficios. Entiendo que Verificar mis ingresos no tendrá acceso continuo a mi información de ingresos.",
        "cbv.submits.show.consent_checkbox_label_html": "<strong>Acepto y confirmo que:</strong><br><strong>Compartiré información precisa.</strong> La información que proporcioné es verdadera y completa a mi leal saber y entender. No compartiré el informe si algo en el mismo es incorrecto.<p><strong>Compartiré cualquier información faltante.</strong> Acepto informarle al Departamento de Servicios Humanos de PA sobre los ingresos que no estén en este informe. <p><strong>No compartiré información falsa.</strong> Entiendo que debo compartir información honesta. Entiendo que podría tener problemas legales si omito información.<p><strong>Compartiré la información de mis ingresos.</strong> Autorizo que la información sobre ingresos que me ha mostrado esta página web se comparta con el Departamento de Servicios Humanos de PA.",
        "cbv.submits.show.pdf.agency_header_name": "Department of Human Services",
        "shared.agency_acronym": "DHS",
        "shared.agency_full_name": "Departamento de Servicios Humanos",
        "shared.agency_portal_name": "COMPASS",
        "shared.app_name": "VerifyMyIncome",
        "shared.benefit": "Asistencia Nutricional",
        "shared.header.cbv_flow_title": "Departamento de Servicios Humanos",
        "shared.header.preheader": "Un sitio web en colaboración con el Departamento de Salud de Pensilvania"
      }
    }
  JSON

  def up
    TRANSLATIONS.each do |group, entries|
      partner_id, locale = group.split("/")
      config = PartnerConfig.find_by(partner_id: partner_id)
      next unless config

      entries.each do |key, value|
        record = config.partner_translations.find_or_initialize_by(locale: locale, key: key)
        record.value = value
        record.save!
      end
    end
  end

  def down
    TRANSLATIONS.each do |group, entries|
      partner_id, locale = group.split("/")
      config = PartnerConfig.find_by(partner_id: partner_id)
      next unless config

      config.partner_translations.where(locale: locale, key: entries.keys).delete_all
    end
  end
end
