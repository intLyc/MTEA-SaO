classdef MTEA_SaO < Algorithm
    % <MT-SO> <None>

    %------------------------------- Reference --------------------------------

    %--------------------------------------------------------------------------

    %------------------------------- Copyright --------------------------------
    % Copyright (c) 2022 Yanchi Li. You are free to use the MTO-Platform for
    % research purposes. All publications which use this platform or any code
    % in the platform should acknowledge the use of "MTO-Platform" and cite
    % or footnote "https://github.com/intLyc/MTO-Platform"
    %--------------------------------------------------------------------------

    properties (SetAccess = private)
        TGap = 10
        TNum = 10
        SaGap = 70
        Memory = 30
        GA_MuC = 2
        GA_MuM = 5
        DE_F = 0.5
        DE_CR = 0.9
    end

    methods
        function parameter = getParameter(obj)
            parameter = {'TGap: Transfer gap', num2str(obj.TGap), ...
                        'TNum:Transfer num per obj.Gen', num2str(obj.TNum), ...
                        'SaGap: Self Adaptive update obj.Gen gap', num2str(obj.SaGap), ...
                        'Memory: Memory obj.Gen num', num2str(obj.Memory), ...
                        'MuC: GA index of Simulated Binary Crossover (tunable)', num2str(obj.GA_MuC), ...
                        'MuM: GA index of polynomial mutation', num2str(obj.GA_MuM), ...
                        'F: DE Mutation Factor', num2str(obj.DE_F), ...
                        'CR: DE Crossover Probability', num2str(obj.DE_CR)};
        end

        function obj = setParameter(obj, parameter_cell)
            count = 1;
            obj.TGap = str2num(parameter_cell{count}); count = count + 1;
            obj.TNum = str2num(parameter_cell{count}); count = count + 1;
            obj.SaGap = str2num(parameter_cell{count}); count = count + 1;
            obj.Memory = str2num(parameter_cell{count}); count = count + 1;
            obj.GA_MuC = str2num(parameter_cell{count}); count = count + 1;
            obj.GA_MuM = str2double(parameter_cell{count}); count = count + 1;
            obj.DE_F = str2double(parameter_cell{count}); count = count + 1;
            obj.DE_CR = str2double(parameter_cell{count}); count = count + 1;
        end

        function run(obj, Prob)
            % Initialization
            population = Initialization(obj, Prob, Individual);
            STNum = 2; % Strategy num
            STN = []; % Strategy population size
            STN(1, :, :) = ones(Prob.T, STNum) * fix(Prob.N / STNum);
            STN(1, :, end) = Prob.N - sum(STN(1, :, 1:end - 1), 3);
            succ = []; fail = [];

            while obj.notTerminated(Prob)
                succ_iter = zeros(Prob.T, STNum);
                fail_iter = zeros(Prob.T, STNum);
                for t = 1:Prob.T
                    parent = population{t};
                    median_Obj(t) = median([parent.Obj]); median_CV(t) = median([parent.CV]);

                    % Knowledge Transfer, only use for generate child
                    if obj.TNum > 0 && mod(obj.Gen - 1, obj.SaGap) + 1 < (obj.SaGap - obj.Memory) && mod(obj.Gen, obj.TGap) == 0
                        transfer_pop = obj.transfer([population(1:t - 1), population(t + 1:end)]);
                        replace = randperm(length(parent), length(transfer_pop));
                        parent(replace) = transfer_pop;
                    end

                    for st = 1:STNum
                        if st == 1
                            STIdx = 1:STN(obj.Gen - 1, t, st);
                        else
                            STIdx = sum(STN(obj.Gen - 1, t, 1:st - 1)) + 1:sum(STN(obj.Gen - 1, t, 1:st));
                        end
                        if isempty(STIdx)
                            continue;
                        end
                        switch st
                            case 1
                                offspring = obj.Generation_GA(parent(STIdx));
                                offspring = obj.Evaluation(offspring, Prob, t);
                                population{t}(STIdx) = Selection_Elit(population{t}(STIdx), offspring);
                            case 2
                                offspring = obj.Generation_DE(parent(STIdx));
                                offspring = obj.Evaluation(offspring, Prob, t);
                                population{t}(STIdx) = Selection_Tournament(population{t}(STIdx), offspring);
                        end

                        succ_iter(t, st) = sum([population{t}(STIdx).CV] < median_CV(t) | ...
                            ([population{t}(STIdx).CV] == median_CV(t) & [population{t}(STIdx).Obj] < median_Obj(t)), 'all');
                        fail_iter(t, st) = sum([population{t}(STIdx).CV] > median_CV(t) | ...
                            ([population{t}(STIdx).CV] == median_CV(t) & [population{t}(STIdx).Obj] > median_Obj(t)), 'all');
                    end
                end

                succ = [succ; succ_iter]; fail = [fail; fail_iter];
                if size(succ, 1) > obj.Memory * Prob.T
                    succ = succ(end - obj.Memory * Prob.T:end, :);
                    fail = fail(end - obj.Memory * Prob.T:end, :);
                end

                % Update population size
                for t = 1:Prob.T
                    succ_t = succ(t:Prob.T:end, :);
                    fail_t = fail(t:Prob.T:end, :);

                    for st = 1:STNum
                        if (sum(succ_t(:, st)) + sum(fail_t(:, st))) == 0
                            succ_p(st) = 0.01;
                        else
                            succ_p(st) = sum(succ_t(:, st)) / (sum(succ_t(:, st)) + sum(fail_t(:, st))) + 0.01;
                        end
                    end

                    succ_old = reshape(STN(obj.Gen - 1, t, :) ./ sum(STN(obj.Gen - 1, t, :)), [1, STNum]);
                    succ_p = succ_old ./ 2 + succ_p;
                    succ_p = succ_p ./ sum(succ_p);

                    if mod(obj.Gen, obj.SaGap) == 0
                        N = fix(succ_p * Prob.N);
                        N(end) = Prob.N - sum(N(1:end - 1));
                        STN(obj.Gen, t, :) = N;
                        population{t} = population{t}(randperm(length(population{t})));
                    else
                        STN(obj.Gen, t, :) = STN(obj.Gen - 1, t, :);
                    end
                end
            end
        end

        function transfer_pop = transfer(obj, archive)
            % random transfer
            for i = 1:obj.TNum
                rand_t = randi([1, length(archive)]);
                rand_p = randi([1, length(archive{rand_t})]);
                transfer_pop(i) = archive{rand_t}(rand_p);
            end
        end

        function offspring = Generation_GA(obj, population)
            if length(population) <= 1
                offspring = population;
                for i = 1:length(population)
                    offspring(i).Dec = GA_Mutation(population(i).Dec, obj.GA_MuM);
                end
                return;
            end
            indorder = randperm(length(population));
            count = 1;
            for i = 1:ceil(length(population) / 2)
                p1 = indorder(i);
                p2 = indorder(i + fix(length(population) / 2));
                offspring(count) = population(p1);
                offspring(count + 1) = population(p2);

                [offspring(count).Dec, offspring(count + 1).Dec] = GA_Crossover(population(p1).Dec, population(p2).Dec, obj.GA_MuC);

                offspring(count).Dec = GA_Mutation(offspring(count).Dec, obj.GA_MuM);
                offspring(count + 1).Dec = GA_Mutation(offspring(count + 1).Dec, obj.GA_MuM);

                for x = count:count + 1
                    offspring(x).Dec(offspring(x).Dec > 1) = 1;
                    offspring(x).Dec(offspring(x).Dec < 0) = 0;
                end
                count = count + 2;
            end
            offspring = offspring(1:length(population));
        end

        function offspring = Generation_DE(obj, population)
            if length(population) < 4
                offspring = population;
                for i = 1:length(population)
                    offspring(i).Dec = GA_Mutation(population(i).Dec, obj.GA_MuM);
                end
                return;
            end
            for i = 1:length(population)
                offspring(i) = population(i);
                A = randperm(length(population), 4);
                A(A == i) = []; x1 = A(1); x2 = A(2); x3 = A(3);

                offspring(i).Dec = population(x1).Dec + obj.DE_F * (population(x2).Dec - population(x3).Dec);
                offspring(i).Dec = DE_Crossover(offspring(i).Dec, population(i).Dec, obj.DE_CR);

                offspring(i).Dec(offspring(i).Dec > 1) = 1;
                offspring(i).Dec(offspring(i).Dec < 0) = 0;
            end
        end
    end
end
