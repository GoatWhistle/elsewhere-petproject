class WidenPriceLevelAndNoteIt < ActiveRecord::Migration[8.1]
  def change
    # Money in minor units is a bigint. A four-byte integer tops out at 21 474 836,47 ₽ — comfortably above a
    # real room rate, and comfortably below what a listing site will actually publish: the harvest met
    # "от 1 400 000 000 руб. средняя цена за номер" on its second pass.
    change_column :properties, :price_level_minor, :bigint

    # Why a property has no observed base. Absence with a reason, never silent absence (hard rule 5).
    add_column :properties, :price_level_note, :string
  end
end
