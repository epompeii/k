from unittest import TestCase

from ..kast import (
    TRUE,
    KApply,
    KLabel,
    KRewrite,
    KSequence,
    KSort,
    KVariable,
    ktokenDots,
)
from ..kastManip import minimize_term, ml_pred_to_bool, push_down_rewrites
from ..prelude import intToken, mlEqualsTrue, mlTop
from .utils import a, b, c, f, k

x = KVariable('X')


class PushDownRewritesTest(TestCase):

    def test_push_down_rewrites(self):
        # Given
        test_data = (
            (KRewrite(KSequence([f(a), b]), KSequence([f(c), b])), KSequence([f(KRewrite(a, c)), b])),
        )

        for i, (before, expected) in enumerate(test_data):
            with self.subTest(i=i):
                # When
                actual = push_down_rewrites(before)

                # Then
                self.assertEqual(actual, expected)


class MinimizeTermTest(TestCase):

    def test_minimize_term(self):
        # Given
        test_data = (
            (f(k(a)), ['<k>'], f(ktokenDots)),
            (f(k(a)), [], f(k(a))),
        )

        for i, (before, abstract_labels, expected) in enumerate(test_data):
            with self.subTest(i=i):
                # When
                actual = minimize_term(before, abstract_labels=abstract_labels)

                # Then
                self.assertEqual(actual, expected)


class MlPredToBoolTest(TestCase):

    def test_ml_pred_to_bool(self):
        # Given
        test_data = (
            (False, KApply(KLabel('#Equals', [KSort('Bool'), KSort('GeneratedTopCell')]), [TRUE, f(a)]), f(a)),
            (False, KApply(KLabel('#Top', [KSort('Bool')])), TRUE),
            (False, KApply('#Top'), TRUE),
            (False, mlTop(), TRUE),
            (False, KApply(KLabel('#Equals'), [x, f(a)]), KApply('_==K_', [x, f(a)])),
            (False, KApply(KLabel('#Equals'), [TRUE, f(a)]), f(a)),
            (False, KApply(KLabel('#Equals', [KSort('Int'), KSort('GeneratedTopCell')]), [intToken(3), f(a)]), KApply('_==K_', [intToken(3), f(a)])),
            (False, KApply(KLabel('#Not', [KSort('GeneratedTopCell')]), [mlTop()]), KApply('notBool_', [TRUE])),
            (True, KApply(KLabel('#Equals'), [f(a), f(x)]), KApply('_==K_', [f(a), f(x)])),
            (False, KApply(KLabel('#And', [KSort('GeneratedTopCell')]), [mlEqualsTrue(TRUE), mlEqualsTrue(TRUE)]), KApply('_andBool_', [TRUE, TRUE]))
        )

        for i, (unsafe, before, expected) in enumerate(test_data):
            with self.subTest(i=i):
                # When
                actual = ml_pred_to_bool(before, unsafe=unsafe)

                # Then
                self.assertEqual(actual, expected)