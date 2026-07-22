module Planning
  # The only four questions this system may interrupt with — a closed list. Asked when impact × ambiguity is
  # high, always with the reason.
  module Clarifications
    module_function

    def for(elements, dream_text)
      by_dimension = elements.to_h { |element| [element["dimension"], element] }

      [
        car_free(by_dimension),
        party(dream_text),
        dates(by_dimension),
        budget_ceiling(by_dimension)
      ].compact
    end

    # Asked only when inferred: a hard constraint nobody stated must be confirmed before it disqualifies.
    def car_free(by_dimension)
      element = by_dimension["car_free"]
      return nil if element.nil? || element["provenance"] == "stated"

      {
        "id" => "car_free", "dimension" => "car_free",
        "question" => "Машина точно недопустима или просто не нужна?",
        "why_it_matters" => "Как жёсткое условие это отсекает направления целиком. Как пожелание — только влияет на выбор трансфера и района.",
        "options" => [{ "value" => true, "label" => "Без машины" }, { "value" => false, "label" => "Можно машину" }]
      }
    end

    def party(dream_text)
      return nil if Lexicon.party(dream_text)

      {
        "id" => "party", "question" => "Сколько человек едет?",
        "why_it_matters" => "От состава зависит и цена перелёта, и то, какие объекты вообще подходят.",
        "options" => [{ "value" => { "adults" => 1 }, "label" => "Один" },
                      { "value" => { "adults" => 2 }, "label" => "Вдвоём" },
                      { "value" => { "adults" => 2, "children" => 1 }, "label" => "Вдвоём с ребёнком" }]
      }
    end

    def dates(by_dimension)
      return nil if by_dimension["dates"]

      {
        "id" => "dates", "dimension" => "dates", "question" => "Когда планируете поехать?",
        "why_it_matters" => "Без дат нельзя ни узнать погоду, ни назвать цену — это единственное, что мы не можем предположить за вас.",
        "options" => []
      }
    end

    # A named budget is a number; whether it is a ceiling is a different question with costly answers.
    def budget_ceiling(by_dimension)
      return nil unless by_dimension["total_budget"]

      {
        "id" => "budget_hard", "dimension" => "total_budget",
        "question" => "Это жёсткий потолок или ориентир?",
        "why_it_matters" => "Жёсткий потолок отсекает варианты дороже него целиком, даже если они лучше по всему остальному.",
        "options" => [{ "value" => true, "label" => "Жёсткий потолок" }, { "value" => false, "label" => "Ориентир" }]
      }
    end
  end
end
